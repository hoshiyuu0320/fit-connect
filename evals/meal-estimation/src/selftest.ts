/**
 * オフラインのハーネス自己テスト（API キー不要・ネットワーク不使用）。失敗があれば exit 1。
 *   npm run selftest
 *
 * ここで使う「応答」はすべて手作りの偽データで、採点・集計コードの検証専用。結果として扱わないこと。
 */
import Anthropic from '@anthropic-ai/sdk'
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import sharp from 'sharp'
import {
  ARMS,
  costFromUsage,
  countImageTokens,
  priceCardFor,
  resizedSize,
  visualTokensFor,
  type ArmId,
} from './arms.js'
import { loadDataset, validateDatasetFile, type DatasetFile, type DatasetSnapshot } from './dataset.js'
import { orderCandidates, parseDishMetadataCsv, parseDishMetadataLine } from './fetch-nutrition5k.js'
import { gradeRun, pareto, type ArmMetrics } from './grade.js'
import { importCustomPhotos, parseCsv, parseLabels } from './import-custom-photos.js'
import {
  buildRequestParams,
  buildUserText,
  clampPositive,
  extractJson,
  extractScreenshotMeta,
  isEmptyResult,
  processResponse,
  validateEstimation,
} from './production-logic.js'
import { EVAL_ROOT, extractPrompts, extractTemplateLiteral, loadProductionPrompts, sha256 } from './prompts.js'
import { renderReport } from './report.js'
import { describeError, main as runMain } from './run.js'
import type { RawRecord, RunMeta } from './run-types.js'
import { bootstrapCI, median } from './stats.js'

const results: Array<{ name: string; ok: boolean; err?: unknown }> = []
async function test(name: string, fn: () => void | Promise<void>): Promise<void> {
  try {
    await fn()
    results.push({ name, ok: true })
    console.log(`  ✔ ${name}`)
  } catch (err) {
    results.push({ name, ok: false, err })
    console.log(`  ✘ ${name}\n      ${String((err as Error)?.stack ?? err).split('\n').slice(0, 6).join('\n      ')}`)
  }
}
const near = (a: number | null | undefined, b: number, eps = 1e-9, msg = '') => {
  assert.ok(a !== null && a !== undefined && Math.abs(a - b) <= eps, `${msg} expected ≈${b}, got ${a}`)
}

const FIXTURES = path.join(EVAL_ROOT, 'src', '__fixtures__')
const PHOTO_FIX = path.join(FIXTURES, 'photos-fixture')
const SHOT_FIX = path.join(FIXTURES, 'screenshots-fixture')
const tmpRoot = mkdtempSync(path.join(os.tmpdir(), 'meal-eval-selftest-'))

// ---------------------------------------------------------------------------
// 偽レコード生成ヘルパ（採点ロジックのテスト専用）
// ---------------------------------------------------------------------------
type T4 = [number, number, number, number]
const tot = ([calories, protein_g, fat_g, carbs_g]: T4) => ({ calories, protein_g, fat_g, carbs_g })
function rec(p: Partial<RawRecord> & Pick<RawRecord, 'case_id' | 'dataset' | 'arm' | 'trial'>): RawRecord {
  return {
    key: `${p.dataset}::${p.case_id}::${p.arm}::${p.trial}`,
    input_kind: 'photo',
    model: ARMS[p.arm].model,
    started_at: '2026-10-09T00:00:00.000Z',
    latency_ms: 1000,
    total_ms: 1000,
    attempts: 1,
    stop_reason: 'end_turn',
    stop_details: null,
    response_model: ARMS[p.arm].model,
    request_id: null,
    usage: null,
    price_card: 'x',
    prompt_tokens: 1000,
    cost_usd: 0.001,
    raw_text: '{}',
    parsed: null,
    parse_error: null,
    app_name: null,
    warning: null,
    empty_result: null,
    outcome: 'ok',
    error: null,
    prod_timeout_exceeded: false,
    ...p,
  }
}
function okRec(dataset: string, case_id: string, arm: ArmId, trial: number, t: T4, extra: Partial<RawRecord> = {}): RawRecord {
  return rec({ dataset, case_id, arm, trial, parsed: { foods: [{ name: 'x', ...tot(t) }], totals: tot(t) }, empty_result: false, outcome: 'ok', ...extra })
}
function emptyRec(dataset: string, case_id: string, arm: ArmId, trial: number, extra: Partial<RawRecord> = {}): RawRecord {
  return rec({ dataset, case_id, arm, trial, parsed: { foods: [], totals: tot([0, 0, 0, 0]) }, empty_result: true, outcome: 'empty', ...extra })
}
function fakeMeta(arms: ArmId[]): RunMeta {
  return {
    schema_version: 1,
    mock: true,
    args: { datasets: [], arms, trials: 2, limit: null, concurrency: 1, out: 'x', resume: null, estimate: false, yes: true, retry_errors: false },
    arms: arms.map((a) => ({ ...ARMS[a], request_shape: {} })),
    baseline_arm: 'sonnet-4-6-prod',
    prompts: { source_path: 'x', sha256_photo: 'a'.repeat(64), sha256_screenshot: 'b'.repeat(64), sha256_source_file: 'c'.repeat(64) },
    datasets: [],
    git: { head: null, production_file_dirty: null },
    sdk_version: null,
    node_version: process.version,
    jpy_per_usd: 150,
    started_at: 'x',
    finished_at: 'y',
    resumed_at: [],
    counts: null,
    notes: [],
  }
}
function snap(name: string, kind: 'photo' | 'screenshot', cases: DatasetSnapshot['cases']): DatasetSnapshot {
  return { name, input_kind: kind, cases_path: 'x', sha256: 'x', cases }
}
function sc(id: string, expected: DatasetSnapshot['cases'][number]['expected']): DatasetSnapshot['cases'][number] {
  return { id, images: ['a.jpg'], meal_type: 'lunch', content: '', expected, tags: [] }
}

// ---------------------------------------------------------------------------
// 偽 API（モック fetch）。ネットワークには一切出ない
// ---------------------------------------------------------------------------
interface Captured {
  url: string
  headers: Record<string, string>
  body: Record<string, unknown>
}
function makeMockFetch(captured: Captured[], opts: { fail400: boolean }) {
  let n = 0
  const json = (status: number, body: unknown) =>
    new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json', 'request-id': `req_mock_${++n}` } })
  return async (input: string | URL | Request, init?: RequestInit): Promise<Response> => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url
    const headers: Record<string, string> = {}
    new Headers(init?.headers).forEach((v, k) => (headers[k] = v))
    const body = JSON.parse(String(init?.body ?? '{}')) as Record<string, unknown>
    captured.push({ url, headers, body })
    if (url.endsWith('/v1/messages/count_tokens')) return json(200, { input_tokens: 1234 })
    if (!url.endsWith('/v1/messages')) return json(404, { type: 'error', error: { type: 'not_found_error', message: 'mock' } })
    const model = body.model as string
    const effort = (body.output_config as { effort?: string } | undefined)?.effort
    const msgs = body.messages as Array<{ content: Array<{ type: string; text?: string }> }>
    const text = msgs[0].content.at(-1)?.text ?? ''
    const sysText = (body.system as Array<{ text: string }>)[0].text
    const isShot = sysText.includes('app_name')
    const usage = { input_tokens: 1500, output_tokens: 300, cache_creation_input_tokens: 0, cache_read_input_tokens: 600, cache_creation: { ephemeral_5m_input_tokens: 0, ephemeral_1h_input_tokens: 0 }, service_tier: 'standard', inference_geo: null, server_tool_use: null, output_tokens_details: null }
    const msg = (content: unknown[], stop_reason = 'end_turn', stop_details: unknown = null) =>
      json(200, { id: `msg_mock_${n}`, type: 'message', role: 'assistant', model, content, stop_reason, stop_sequence: null, stop_details, usage, container: null, diagnostics: null })
    const thinking = { type: 'thinking', thinking: '', signature: 'sig' }
    const answer = isShot
      ? { foods: [{ name: '合計', calories: 712, protein_g: 0, fat_g: 0, carbs_g: 0 }], totals: { calories: 712, protein_g: 31, fat_g: 24, carbs_g: 93 }, app_name: 'あすけん', warning: model === 'claude-sonnet-4-6' && text.includes('SCN:warn') ? '合計が噛み合いません' : null }
      : { foods: [{ name: 'ご飯', calories: 300, protein_g: 5, fat_g: 1, carbs_g: 65 }, { name: '唐揚げ', calories: 300, protein_g: 20, fat_g: 18, carbs_g: 10 }], totals: { calories: 1, protein_g: 1, fat_g: 1, carbs_g: 1 } }
    if (text.includes('SCN:err400') && model === 'claude-haiku-5-5' && effort === 'medium' && opts.fail400) {
      return json(400, { type: 'error', error: { type: 'invalid_request_error', message: 'mock bad request' } })
    }
    if (text.includes('SCN:refusal') && model === 'claude-sonnet-5-5') {
      return msg([], 'refusal', { type: 'refusal', category: 'general_harms', explanation: 'mock' })
    }
    if (text.includes('SCN:maxtok') && model === 'claude-haiku-5-5' && effort === 'low') return msg([thinking], 'max_tokens')
    if (text.includes('SCN:empty')) return msg([{ type: 'text', text: JSON.stringify({ foods: [], totals: { calories: 0, protein_g: 0, fat_g: 0, carbs_g: 0 } }), citations: null }])
    const body2 = text.includes('SCN:fenced') ? '```json\n' + JSON.stringify(answer) + '\n```' : JSON.stringify(answer)
    const content = effort === 'medium' ? [thinking, { type: 'text', text: body2, citations: null }] : [{ type: 'text', text: body2, citations: null }]
    return msg(content)
  }
}

async function run(): Promise<void> {
  console.log('== prompts ==')
  await test('本番 index.ts から 2 つのプロンプトとハッシュを抽出できる', () => {
    const p = loadProductionPrompts()
    assert.ok(p.photo.startsWith('あなたは栄養素推定アシスタントです'), 'SYSTEM_PROMPT の冒頭')
    assert.ok(p.screenshot.includes('app_name'), 'SCREENSHOT_SYSTEM_PROMPT に app_name')
    assert.notEqual(p.photo, p.screenshot)
    assert.match(p.sha256.photo, /^[0-9a-f]{64}$/)
    assert.equal(p.sha256.photo, sha256(p.photo))
    assert.equal(p.sha256.screenshot, sha256(p.screenshot))
    assert.ok(!p.photo.includes('`'), 'バッククォートを含まない（終端を正しく検出）')
  })
  await test('テンプレートリテラル抽出: エスケープ解決・未定義/置換ありは明示的エラー', () => {
    const src = 'const A = `x\\`y\\n\\u3042${"$"}`\nconst B = `a\nb`'
    assert.throws(() => extractTemplateLiteral(src, 'A'), /置換/)
    const src2 = 'const A = `x\\`y\\n\\u3042\\${z}`\nconst B: string = `a\r\nb`'
    assert.equal(extractTemplateLiteral(src2, 'A'), 'x`y\nあ${z}')
    assert.equal(extractTemplateLiteral(src2, 'B'), 'a\nb')
    assert.throws(() => extractTemplateLiteral(src2, 'SYSTEM_PROMPT', 'test.ts'), /見つかりません/)
    assert.throws(() => extractPrompts('const SYSTEM_PROMPT = `"foods" ' + 'x'.repeat(60) + '`'), /SCREENSHOT_SYSTEM_PROMPT/)
  })

  console.log('== production-logic ==')
  await test('移植元の行番号が本番 index.ts と一致（本番が変わったら移植の見直しが必要）', () => {
    const lines = readFileSync(path.join(EVAL_ROOT, '..', '..', 'supabase', 'functions', 'estimate-meal-nutrition', 'index.ts'), 'utf8').split('\n')
    const at = (n: number) => lines[n - 1] ?? ''
    const expectAt: Array<[number, string]> = [
      [71, "const model = hasImages ? 'claude-sonnet-4-6' : 'claude-haiku-4-5'"],
      [77, 'const textPart = content && content.trim().length > 0'],
      [92, 'max_tokens: 1024,'],
      [93, 'temperature: 0.2,'],
      [98, "cache_control: { type: 'ephemeral' },"],
      [109, "const textBlock = data.content?.find((b: any) => b.type === 'text')"],
      [145, 'function extractJson(text: string): string {'],
      [160, 'function clampPositive(n: any): number {'],
      [166, 'function validateEstimation(raw: any, trustTotals: boolean): { foods: any[]; totals: any } {'],
      [302, "const contentStr = typeof content === 'string' ? content : ''"],
      [440, "result = validateEstimation(raw, inputKind === 'screenshot')"],
      [442, "appName = typeof raw.app_name === 'string' && raw.app_name.trim().length > 0"],
      [461, 'if (result.foods.length === 0) {'],
    ]
    for (const [n, frag] of expectAt) assert.ok(at(n).includes(frag), `index.ts L${n} に「${frag}」が無い（実際: ${at(n).trim()}）。production-logic.ts の移植を見直すこと`)
  })

  await test('extractJson: コードフェンス / 前後の説明文 / 素の JSON', () => {
    assert.equal(extractJson('```json\n{"a":1}\n```'), '{"a":1}')
    assert.equal(extractJson('```\n{"a":1}\n```'), '{"a":1}')
    assert.equal(extractJson('以下が結果です:\n{"a":{"b":2}}\n以上'), '{"a":{"b":2}}')
    assert.equal(extractJson('  {"a":1}  '), '{"a":1}')
    assert.equal(extractJson('no json'), 'no json')
  })
  await test('clampPositive: 負数・NaN・文字列・小数切り捨て', () => {
    assert.equal(clampPositive(-5), 0)
    assert.equal(clampPositive(Number.NaN), 0)
    assert.equal(clampPositive('abc'), 0)
    assert.equal(clampPositive('12.9g'), 12)
    assert.equal(clampPositive(99.99), 99)
    assert.equal(clampPositive(null), 0)
    assert.equal(clampPositive(undefined), 0)
  })
  await test('validateEstimation(photo): totals は foods から再計算（モデルの totals は無視）', () => {
    const r = validateEstimation({ foods: [{ name: 'a', calories: 100.9, protein_g: '5.5', fat_g: -3, carbs_g: Number.NaN }, { name: 'b', calories: 50, protein_g: 1, fat_g: 2, carbs_g: 3 }], totals: { calories: 9999, protein_g: 9, fat_g: 9, carbs_g: 9 } }, false)
    assert.deepEqual(r.foods[0], { name: 'a', calories: 100, protein_g: 5, fat_g: 0, carbs_g: 0 })
    assert.deepEqual(r.totals, { calories: 150, protein_g: 6, fat_g: 2, carbs_g: 3 })
  })
  await test('validateEstimation(screenshot): 画面の totals を信頼（clamp のみ）', () => {
    const r = validateEstimation({ foods: [{ name: '合計', calories: 712, protein_g: 0, fat_g: 0, carbs_g: 0 }], totals: { calories: '712.6', protein_g: 31.9, fat_g: -1, carbs_g: 93 } }, true)
    assert.deepEqual(r.totals, { calories: 712, protein_g: 31, fat_g: 0, carbs_g: 93 })
  })
  await test('validateEstimation: 本番と同じエラーメッセージで throw', () => {
    assert.throws(() => validateEstimation(null, false), /Invalid response shape/)
    assert.throws(() => validateEstimation({ totals: {} }, false), /Missing foods array/)
    assert.throws(() => validateEstimation({ foods: [] }, false), /Missing totals/)
    assert.throws(() => validateEstimation({ foods: [{ calories: 1 }], totals: {} }, false), /Food missing name/)
  })
  await test('ユーザーテキスト構築・app_name/warning 抽出・EMPTY 判定', () => {
    assert.equal(buildUserText('lunch', ''), '食事タイプ: lunch\n補足: (なし、画像のみ)')
    assert.equal(buildUserText('lunch', '   '), '食事タイプ: lunch\n補足: (なし、画像のみ)')
    assert.equal(buildUserText('dinner', '  ご飯大盛り \n'), '食事タイプ: dinner\n補足: ご飯大盛り')
    assert.equal(buildUserText('snack', 42), '食事タイプ: snack\n補足: (なし、画像のみ)')
    assert.deepEqual(extractScreenshotMeta({ app_name: '  ', warning: '  ' }), { app_name: 'unknown', warning: null })
    assert.deepEqual(extractScreenshotMeta({ app_name: ' カロミル ', warning: ' 噛み合いません ' }), { app_name: 'カロミル', warning: '噛み合いません' })
    assert.deepEqual(extractScreenshotMeta({}), { app_name: 'unknown', warning: null })
    assert.equal(isEmptyResult({ foods: [], totals: tot([0, 0, 0, 0]) }), true)
  })
  await test('processResponse: thinking 先頭でも text を type で選ぶ / refusal / max_tokens / 空', () => {
    const json = JSON.stringify({ foods: [{ name: 'a', calories: 10, protein_g: 1, fat_g: 1, carbs_g: 1 }], totals: { calories: 0, protein_g: 0, fat_g: 0, carbs_g: 0 } })
    const thinking = { type: 'thinking', thinking: '', signature: 's' } as unknown as Anthropic.ContentBlock
    const text = (t: string) => ({ type: 'text', text: t, citations: null }) as Anthropic.ContentBlock
    const a = processResponse({ content: [thinking, text(json)], stop_reason: 'end_turn' }, 'photo')
    assert.equal(a.outcome, 'ok')
    assert.equal(a.parsed?.totals.calories, 10)
    assert.equal(a.app_name, null)
    const b = processResponse({ content: [], stop_reason: 'refusal' }, 'photo')
    assert.equal(b.outcome, 'refusal')
    const c = processResponse({ content: [thinking], stop_reason: 'max_tokens' }, 'photo')
    assert.equal(c.outcome, 'parse_fail')
    assert.equal(c.parse_error, 'No text in Claude response')
    const d = processResponse({ content: [text('{"foods":[{"name":"a","calo')], stop_reason: 'max_tokens' }, 'photo')
    assert.equal(d.outcome, 'parse_fail')
    const e = processResponse({ content: [text('{"foods":[],"totals":{"calories":0}}')], stop_reason: 'end_turn' }, 'screenshot')
    assert.equal(e.outcome, 'empty')
    assert.equal(e.empty_result, true)
    assert.equal(e.app_name, 'unknown')
  })
  await test('リクエスト形状: 画像→テキスト、system は cache_control 付き 1 ブロック、アーム別パラメータ', () => {
    const imgs = ['AAAA', 'BBBB']
    const base = buildRequestParams(ARMS['sonnet-4-6-prod'], 'SYS', imgs, 'lunch', '')
    assert.equal(base.model, 'claude-sonnet-4-6')
    assert.equal(base.max_tokens, 1024)
    assert.equal(base.temperature, 0.2)
    assert.equal(base.output_config, undefined)
    assert.deepEqual(base.system, [{ type: 'text', text: 'SYS', cache_control: { type: 'ephemeral' } }])
    const content = base.messages[0].content as Array<{ type: string; source?: { type: string; media_type: string } }>
    assert.deepEqual(content.map((b) => b.type), ['image', 'image', 'text'])
    assert.deepEqual(content[0].source && { type: content[0].source.type, media_type: content[0].source.media_type }, { type: 'base64', media_type: 'image/jpeg' })
    for (const id of ['haiku-5-5-low', 'haiku-5-5-medium', 'sonnet-5-5-low'] as ArmId[]) {
      const p = buildRequestParams(ARMS[id], 'SYS', imgs, 'lunch', '') as unknown as Record<string, unknown>
      for (const k of ['temperature', 'top_p', 'top_k', 'thinking', 'fallbacks']) assert.ok(!(k in p), `${id} に ${k} を送ってはいけない`)
      assert.equal(p.max_tokens, 4096)
      assert.deepEqual(p.output_config, { effort: ARMS[id].effort })
    }
    assert.throws(() => buildRequestParams(ARMS['haiku-5-5-low'], 'S', ['a', 'b', 'c', 'd'], 'lunch', ''))
  })

  console.log('== vision / price ==')
  await test('resizedSize: ドキュメントの例と一致', () => {
    assert.deepEqual(resizedSize(1075, 1520), [924, 1307]) // 標準ティア（A4 スキャン）
    assert.deepEqual(resizedSize(1920, 1080), [1456, 819]) // 標準ティア
    assert.deepEqual(resizedSize(1920, 1080, 2576, 4784), [1920, 1080]) // 高解像度ティアは縮小なし
    assert.deepEqual(resizedSize(1075, 1520, 2576, 4784), [1075, 1520])
    // Vision ドキュメントの表は 1269x952 だが、同ドキュメントの参照実装は 1270x952 を返す
    // （1270/1.333.. = 952.5 → 偶数丸めで 952、46×34 = 1564 tokens で収まる）。トークン数はどちらも 1564。
    assert.deepEqual(resizedSize(2000, 1500), [1270, 952])
    assert.equal(visualTokensFor(2000, 1500, 'standard').tokens, 1564)
    assert.deepEqual(resizedSize(3840, 2160, 2576, 4784), [2576, 1449])
    assert.deepEqual(resizedSize(3840, 2160), [1456, 819])
    assert.deepEqual(resizedSize(200, 200), [200, 200])
    assert.equal(countImageTokens(1456, 819), 1560)
    assert.equal(visualTokensFor(1920, 1080, 'high-res').tokens, 2691)
    assert.equal(visualTokensFor(2000, 1500, 'high-res').tokens, 3888)
    assert.equal(visualTokensFor(3840, 2160, 'high-res').tokens, 4784)
    assert.equal(visualTokensFor(1000, 1000, 'standard').tokens, 1296)
    assert.equal(visualTokensFor(1092, 1092, 'standard').tokens, 1521)
    assert.equal(visualTokensFor(2000, 1500, 'standard').tokens, 1564)
    // 縦長スクショ（アプリ縮小後 499x1080）は両ティアとも縮小なし
    assert.deepEqual(visualTokensFor(499, 1080, 'standard'), { resized: [499, 1080], tokens: 18 * 39 })
  })
  await test('料金: 実測 usage からのコストとレートカード（Haiku 5.5 の 100K 境界はキャッシュ込み）', () => {
    const s46 = costFromUsage('claude-sonnet-4-6', { input_tokens: 2000, output_tokens: 400, cache_creation_input_tokens: 0, cache_read_input_tokens: 0 })
    near(s46.cost_usd, 0.012, 1e-12)
    assert.equal(s46.price_card, 'sonnet-4-6')
    const s46c = costFromUsage('claude-sonnet-4-6', { input_tokens: 100, output_tokens: 0, cache_creation_input_tokens: 1000, cache_read_input_tokens: 1000 })
    near(s46c.cost_usd, (100 * 3 + 1000 * 3.75 + 1000 * 0.3) / 1e6, 1e-15)
    const s55 = costFromUsage('claude-sonnet-5-5', { input_tokens: 1000, output_tokens: 1000, cache_creation_input_tokens: 0, cache_read_input_tokens: 1000 })
    near(s55.cost_usd, (1000 * 2 + 1000 * 0.1 + 1000 * 10) / 1e6, 1e-15)
    const h = costFromUsage('claude-haiku-5-5', { input_tokens: 3000, output_tokens: 1000, cache_creation_input_tokens: 500, cache_read_input_tokens: 500 })
    assert.equal(h.price_card, 'haiku-5-5:<=100K')
    assert.equal(h.prompt_tokens, 4000)
    near(h.cost_usd, (3000 * 0.1 + 500 * 0.125 + 500 * 0.01 + 1000 * 0.5) / 1e6, 1e-15)
    assert.equal(priceCardFor('claude-haiku-5-5', 100_000).name, 'haiku-5-5:<=100K')
    const long = costFromUsage('claude-haiku-5-5', { input_tokens: 60_000, output_tokens: 1000, cache_creation_input_tokens: 0, cache_read_input_tokens: 40_001 })
    assert.equal(long.price_card, 'haiku-5-5:>100K', 'input 単独は 100K 未満でもキャッシュ読み取り込みで超えれば高額カード')
    near(long.cost_usd, (60_000 * 0.5 + 40_001 * 0.05 + 1000 * 2.5) / 1e6, 1e-15)
    const h1 = costFromUsage('claude-haiku-5-5', { input_tokens: 0, output_tokens: 0, cache_creation_input_tokens: 1000, cache_read_input_tokens: 0, cache_creation: { ephemeral_5m_input_tokens: 600, ephemeral_1h_input_tokens: 400 } })
    near(h1.cost_usd, (600 * 0.125 + 400 * 0.2) / 1e6, 1e-15)
  })

  console.log('== CSV パーサ ==')
  await test('Nutrition5k メタデータ: 先頭 6 列のみ解釈・不正行はスキップ', () => {
    const good = 'dish_1561662216,300.794281,193.000000,12.387489,28.218290,18.633970,ingr_0000000508,soy sauce,3.398568,1.80,0.02,0.16,0.27'
    assert.deepEqual(parseDishMetadataLine(good), { dish_id: 'dish_1561662216', total_calories: 300.794281, total_mass: 193, total_fat: 12.387489, total_carb: 28.21829, total_protein: 18.63397 })
    assert.equal(parseDishMetadataLine('dish_1,100,200,3,4'), null, '列不足')
    assert.equal(parseDishMetadataLine('dish_1,abc,200,3,4,5'), null, '非数値')
    assert.equal(parseDishMetadataLine('dish_1,1e2,200,3,4,-5'), null, '負数')
    assert.equal(parseDishMetadataLine('dish_1,NaN,200,3,4,5'), null, 'NaN')
    assert.equal(parseDishMetadataLine('foo_1,100,200,3,4,5'), null, 'dish_id 形式')
    assert.equal(parseDishMetadataLine('dish_id,total_calories,total_mass,total_fat,total_carb,total_protein'), null, 'ヘッダー行')
    assert.equal(parseDishMetadataLine('dish_2,100,200,3,4,5\r')?.total_protein, 5, 'CRLF')
    const csv = [good, 'dish_2,40,10,1,1,1', 'dish_3,1600,10,1,1,1', 'broken line', '', 'dish_4,800,300,30,90,40,ingr_x,rice,1,2,3,4,5', 'dish_4,800,300,30,90,40'].join('\n')
    const parsed = parseDishMetadataCsv(csv)
    assert.equal(parsed.dishes.length, 5)
    assert.equal(parsed.skipped, 1)
    const ordered = orderCandidates(parsed.dishes, 42)
    assert.deepEqual(ordered.map((d) => d.dish_id).sort(), ['dish_1561662216', 'dish_4'], 'kcal 50〜1500 で絞り、重複除去')
    assert.deepEqual(orderCandidates(parsed.dishes, 42), ordered, 'シードが同じなら同じ順序')
  })
  await test('labels.csv: RFC 4180（引用符・カンマ・改行・BOM・CRLF）と検証', () => {
    assert.deepEqual(parseCsv('﻿a,b\r\n"x, y","he said ""hi"""\n"multi\nline",\n'), [['a', 'b'], ['x, y', 'he said "hi"'], ['multi\nline', '']])
    const header = 'id,files,meal_type,content,calories,protein_g,fat_g,carbs_g,note,is_meal'
    const ok = parseLabels([header, 'c-1,a.jpg;b.jpg,lunch,"ご飯大盛り, 味噌汁",498.4,18,15,72,セブン 幕の内,', 'c-2,c.jpg,dinner,,,,,,不明,', 'c-3,d.jpg,snack,,,,,,風景,false'].join('\n'), null)
    assert.deepEqual(ok.errors, [])
    assert.deepEqual(ok.rows[0].files, ['a.jpg', 'b.jpg'])
    assert.equal(ok.rows[0].content, 'ご飯大盛り, 味噌汁')
    assert.deepEqual(ok.rows[0].totals, { calories: 498, protein_g: 18, fat_g: 15, carbs_g: 72 })
    assert.equal(ok.rows[1].totals, null)
    assert.equal(ok.rows[2].is_meal, false)
    const bad = parseLabels([header, 'c-1,a.jpg;b.jpg;c.jpg;d.jpg,brunch,,1,,3,4,,', 'c-1,../x.jpg,lunch,,,,,,,maybe'].join('\n'), null)
    const msg = bad.errors.join('\n')
    for (const frag of ['1〜3 件', 'meal_type', '4 つとも', '重複', '相対パス', 'is_meal']) assert.ok(msg.includes(frag), `エラーに「${frag}」を含む: ${msg}`)
    assert.ok(parseLabels('id,files\n', null).errors.some((e) => e.includes('meal_type')), '必須列不足')
  })

  await test('import:custom: raw/ → images/（向き補正・1920x1080 枠・メタデータ除去）→ 契約どおりの cases.json', async () => {
    const dir = path.join(tmpRoot, 'photos-custom')
    mkdirSync(path.join(dir, 'raw'), { recursive: true })
    // 4032x3024 の横長画像に EXIF Orientation=6（90° 回転）→ 表示上は縦長 3024x4032 → 810x1080 になるはず
    await sharp({ create: { width: 4032, height: 3024, channels: 3, background: { r: 120, g: 80, b: 40 } } })
      .jpeg({ quality: 90 })
      .withMetadata({ orientation: 6 })
      .toFile(path.join(dir, 'raw', 'IMG_1.jpg'))
    await sharp({ create: { width: 640, height: 480, channels: 3, background: { r: 10, g: 200, b: 10 } } }).png().toFile(path.join(dir, 'raw', 'small.png'))
    writeFileSync(path.join(dir, 'labels.csv'), ['id,files,meal_type,content,calories,protein_g,fat_g,carbs_g,note', 'c-1,IMG_1.jpg;small.png,lunch,"大盛り, 汁物なし",650.4,25,20,90,テスト', 'c-2,small.png,snack,,,,,,正解不明'].join('\n'))
    const logs: string[] = []
    assert.equal(await importCustomPhotos(dir, (x) => logs.push(x), (x) => logs.push(x)), 0, logs.join('\n'))
    const ds = loadDataset(dir)
    assert.equal(ds.name, 'photos-custom')
    assert.equal(ds.file.cases.length, 2)
    assert.deepEqual(ds.file.cases[0].expected, { is_meal: true, totals: { calories: 650, protein_g: 25, fat_g: 20, carbs_g: 90 } })
    assert.equal(ds.file.cases[0].content, '大盛り, 汁物なし')
    assert.equal(ds.file.cases[1].expected.totals, null)
    const m1 = await sharp(path.join(dir, 'images', 'c-1_1.jpg')).metadata()
    assert.deepEqual([m1.width, m1.height, m1.format, m1.orientation, m1.exif], [810, 1080, 'jpeg', undefined, undefined])
    const m2 = await sharp(path.join(dir, 'images', 'c-1_2.jpg')).metadata()
    assert.deepEqual([m2.width, m2.height, m2.format], [640, 480, 'jpeg'], '拡大しない・PNG も JPEG に')
    writeFileSync(path.join(dir, 'labels.csv'), 'id,files,meal_type,content,calories,protein_g,fat_g,carbs_g,note\nc-9,missing.jpg,lunch,,1,2,3,4,\n')
    const before = readFileSync(path.join(dir, 'cases.json'), 'utf8')
    assert.equal(await importCustomPhotos(dir, () => {}, () => {}), 1)
    assert.equal(readFileSync(path.join(dir, 'cases.json'), 'utf8'), before, 'エラー時は cases.json を書き換えない')
  })

  console.log('== データセット契約 ==')
  await test('フィクスチャが契約どおりに読め、契約違反は列挙される', () => {
    const p = loadDataset(PHOTO_FIX)
    const s = loadDataset(SHOT_FIX)
    assert.equal(p.input_kind, 'photo')
    assert.equal(s.input_kind, 'screenshot')
    const bad = { dataset: 'x', input_kind: 'video', description: '', source: '', preprocessing: '', cases: [{ id: 'a', images: ['../../etc/passwd'], meal_type: 'brunch', content: 1, expected: { is_meal: false, totals: { calories: 1, protein_g: 1, fat_g: 1, carbs_g: 1 } }, tags: [] }] }
    const errs = validateDatasetFile(bad, PHOTO_FIX).join('\n')
    for (const frag of ['input_kind', 'ディレクトリ外', 'meal_type', 'content', 'is_meal=false']) assert.ok(errs.includes(frag), `「${frag}」: ${errs}`)
    const pngDir = path.join(tmpRoot, 'png-ds')
    mkdirSync(pngDir, { recursive: true })
    writeFileSync(path.join(pngDir, 'a.jpg'), Buffer.from([0x89, 0x50, 0x4e, 0x47]))
    const pngFile: DatasetFile = { dataset: 'png', input_kind: 'photo', description: '', source: '', preprocessing: '', cases: [{ id: 'a', images: ['a.jpg'], meal_type: 'lunch', content: '', expected: { is_meal: true, totals: null }, tags: [] }] }
    assert.ok(validateDatasetFile(pngFile, pngDir).some((e) => e.includes('JPEG ではありません')))
  })

  console.log('== grader（手作りの偽応答で検証。結果ではない） ==')
  await test('写真: APE 中央値/p90/平均・MAE・±20%・PFC・false-EMPTY・CV・対応あり Δ', () => {
    const D = 'g-photo'
    const B: ArmId = 'sonnet-4-6-prod'
    const C: ArmId = 'haiku-5-5-low'
    const cases = [sc('c1', { is_meal: true, totals: tot([500, 20, 10, 80]) }), sc('c2', { is_meal: true, totals: tot([1000, 40, 30, 120]), alt_totals: [tot([2000, 80, 60, 240])] })]
    const recs = [
      okRec(D, 'c1', B, 1, [550, 22, 10, 80]), okRec(D, 'c1', B, 2, [450, 18, 10, 80]),
      okRec(D, 'c2', B, 1, [900, 40, 30, 120]), okRec(D, 'c2', B, 2, [1100, 40, 30, 120]),
      okRec(D, 'c1', C, 1, [600, 30, 10, 80]), okRec(D, 'c1', C, 2, [400, 20, 10, 80]),
      emptyRec(D, 'c2', C, 1), okRec(D, 'c2', C, 2, [1300, 40, 30, 120]),
      rec({ dataset: D, case_id: 'c2', arm: C, trial: 3, outcome: 'error', error: { type: 'rate_limit_error', status: 429, message: 'x' }, cost_usd: null, latency_ms: null }),
    ]
    const s = gradeRun(fakeMeta([B, C]), [snap(D, 'photo', cases)], recs)
    const ds = s.datasets[0]
    const b = ds.arms.find((m) => m.arm === B)!
    const c = ds.arms.find((m) => m.arm === C)!
    near(b.photo!.ape_median, 0.1, 1e-12)
    near(b.photo!.ape_p90, 0.1, 1e-12)
    near(c.photo!.ape_median, 0.2, 1e-12)
    near(c.photo!.ape_p90, 0.28, 1e-12)
    near(c.photo!.ape_mean, 0.7 / 3, 1e-12)
    near(c.photo!.mae_kcal, 500 / 3, 1e-9)
    near(c.photo!.mae_protein_g, 10 / 3, 1e-9)
    assert.deepEqual([c.photo!.within20.num, c.photo!.within20.den], [2, 3])
    assert.deepEqual([c.false_empty.num, c.false_empty.den], [1, 4], 'API エラーは分母から除外')
    assert.deepEqual([c.error.num, c.error.den], [1, 5])
    near(b.photo!.cv_median, Math.sqrt(5000) / 500, 1e-12)
    assert.equal(c.photo!.n_cases_cv, 1, '成功 2 試行以上のケースのみ')
    const cmp = ds.comparisons[0]
    assert.equal(cmp.paired_cases, 2)
    near(cmp.photo!.delta_ape_median!.estimate, 0.15, 1e-12)
    assert.equal(cmp.decision.verdict, 'INSUFFICIENT DATA')
    assert.equal(cmp.worst.length, 1)
    assert.equal(cmp.worst[0].case_id, 'c2')
    near(b.mean_cost_jpy, 0.15, 1e-12)
    near(b.jpy_per_1000_calls, 150, 1e-9)
  })
  await test('スクショ: 項目別（alt 可）・4 項目同時（同一期待値セット）・warning・品目数・アプリ名・正しい拒否', () => {
    const D = 'g-shot'
    const B: ArmId = 'sonnet-4-6-prod'
    const cases = [
      sc('s1', { is_meal: true, totals: tot([700, 30, 20, 90]), alt_totals: [tot([350, 15, 10, 45])], foods_count: 2, expect_warning: false, app_name: 'あすけん' }),
      sc('s2', { is_meal: true, totals: tot([500, 20, 15, 70]), expect_warning: true }),
      sc('s3', { is_meal: false, totals: null }),
    ]
    const two = (t: T4) => ({ foods: [{ name: 'a', ...tot(t) }, { name: 'b', calories: 0, protein_g: 0, fat_g: 0, carbs_g: 0 }], totals: tot(t) })
    const recs = [
      okRec(D, 's1', B, 1, [701, 30, 19, 91], { input_kind: 'screenshot', parsed: two([701, 30, 19, 91]), app_name: 'あすけん ', warning: null }),
      okRec(D, 's1', B, 2, [350, 15, 20, 45], { input_kind: 'screenshot', app_name: 'カロミル', warning: 'w', parsed: { foods: [1, 2, 3].map((i) => ({ name: `f${i}`, ...tot([0, 0, 0, 0]) })), totals: tot([350, 15, 20, 45]) } }),
      rec({ dataset: D, case_id: 's2', arm: B, trial: 1, input_kind: 'screenshot', outcome: 'parse_fail', parse_error: 'x' }),
      okRec(D, 's2', B, 2, [500, 22, 15, 70], { input_kind: 'screenshot', warning: 'w', app_name: 'unknown' }),
      emptyRec(D, 's3', B, 1, { input_kind: 'screenshot' }),
      rec({ dataset: D, case_id: 's3', arm: B, trial: 2, outcome: 'error', error: { type: 'timeout', status: null, message: 'x' } }),
    ]
    const m = gradeRun(fakeMeta([B]), [snap(D, 'screenshot', cases)], recs).datasets[0].arms[0]
    const sm = m.screenshot!
    const nd = (r: { num: number; den: number }) => [r.num, r.den]
    assert.deepEqual(nd(sm.field_correct.calories), [3, 4])
    assert.deepEqual(nd(sm.field_correct.protein_g), [2, 4])
    assert.deepEqual(nd(sm.field_correct.fat_g), [3, 4])
    assert.deepEqual(nd(sm.field_correct.carbs_g), [3, 4])
    assert.deepEqual(nd(sm.all_four_correct), [1, 4], '項目を別々の期待値から拾った試行は 4 項目同時正解にしない')
    assert.deepEqual(nd(sm.warning_accuracy), [2, 4])
    assert.deepEqual(nd(sm.foods_count_exact), [1, 2])
    assert.deepEqual(nd(sm.app_name_match), [1, 2])
    assert.deepEqual(nd(m.correct_rejection), [1, 1])
    assert.deepEqual(nd(m.false_empty), [0, 4])
    assert.deepEqual(nd(m.parse_fail), [1, 6])
  })
  await test('判定ルール: PASS / FAIL（APE）/ FAIL（false-EMPTY）/ INSUFFICIENT DATA', () => {
    const B: ArmId = 'sonnet-4-6-prod'
    const C: ArmId = 'haiku-5-5-low'
    const mk = (n: number, candFactor: number, emptyCases: number) => {
      const cases = Array.from({ length: n }, (_, i) => sc(`c${i}`, { is_meal: true, totals: tot([1000, 40, 30, 120]) }))
      const recs: RawRecord[] = []
      cases.forEach((c, i) => {
        recs.push(okRec('d', c.id, B, 1, [1100, 40, 30, 120]), okRec('d', c.id, B, 2, [900, 40, 30, 120]))
        const k = 1000 * (1 + 0.1 * candFactor)
        recs.push(okRec('d', c.id, C, 1, [k, 40, 30, 120]))
        recs.push(i < emptyCases ? emptyRec('d', c.id, C, 2) : okRec('d', c.id, C, 2, [k, 40, 30, 120]))
      })
      return gradeRun(fakeMeta([B, C]), [snap('d', 'photo', cases)], recs).datasets[0].comparisons[0].decision
    }
    assert.equal(mk(25, 1.05, 0).verdict, 'PASS')
    assert.equal(mk(25, 1.2, 0).verdict, 'FAIL')
    const fe = mk(25, 1.0, 3)
    assert.equal(fe.verdict, 'FAIL', '6% > 0% + 2pt')
    assert.equal(fe.clauses[0].pass, true)
    assert.equal(fe.clauses[1].pass, false)
    assert.equal(mk(25, 1.0, 1).verdict, 'PASS', '2% ≤ 0% + 2pt（境界）')
    assert.equal(mk(19, 1.0, 0).verdict, 'INSUFFICIENT DATA')
  })
  await test('スクショ判定: warning ケースが無ければ INSUFFICIENT DATA、揃えば PASS/FAIL', () => {
    const B: ArmId = 'sonnet-4-6-prod'
    const C: ArmId = 'haiku-5-5-medium'
    const build = (withWarn: boolean, candWrong: number) => {
      const cases = Array.from({ length: 24 }, (_, i) => sc(`s${i}`, { is_meal: true, totals: tot([600, 20, 20, 80]), expect_warning: withWarn ? i % 2 === 0 : null }))
      cases.push(sc('nm', { is_meal: false, totals: null }))
      const recs: RawRecord[] = []
      for (const c of cases) {
        if (!c.expected.is_meal) {
          recs.push(emptyRec('d', c.id, B, 1, { input_kind: 'screenshot' }), emptyRec('d', c.id, C, 1, { input_kind: 'screenshot' }))
          continue
        }
        const w = c.expected.expect_warning ? 'w' : null
        recs.push(okRec('d', c.id, B, 1, [600, 20, 20, 80], { input_kind: 'screenshot', warning: w }))
        const idx = Number(c.id.slice(1))
        recs.push(okRec('d', c.id, C, 1, idx < candWrong ? [650, 20, 20, 80] : [600, 20, 20, 80], { input_kind: 'screenshot', warning: w }))
      }
      return gradeRun(fakeMeta([B, C]), [snap('d', 'screenshot', cases)], recs).datasets[0].comparisons[0]
    }
    assert.equal(build(false, 0).decision.verdict, 'INSUFFICIENT DATA')
    assert.equal(build(true, 0).decision.verdict, 'PASS')
    const f = build(true, 2)
    assert.equal(f.decision.verdict, 'FAIL', '2/24 = 8.3pt 悪化')
    near(f.screenshot!.delta_all4_mean!.estimate, -2 / 24, 1e-12)
    assert.equal(f.worst.length, 3)
    assert.ok(f.worst.slice(0, 2).every((w) => w.delta < 0))
  })
  await test('重複キーは最後の行を採用・パレート判定・ブートストラップの決定性', () => {
    const B: ArmId = 'sonnet-4-6-prod'
    const cases = [sc('c1', { is_meal: true, totals: tot([500, 20, 10, 80]) })]
    const first = rec({ dataset: 'd', case_id: 'c1', arm: B, trial: 1, outcome: 'error', error: { type: 'x', status: 500, message: 'x' } })
    const s = gradeRun(fakeMeta([B]), [snap('d', 'photo', cases)], [first, okRec('d', 'c1', B, 1, [500, 20, 10, 80])])
    assert.equal(s.n_records, 1)
    assert.equal(s.datasets[0].arms[0].error.num, 0)
    const fake = (arm: ArmId, ape: number, cost: number) => ({ arm, mean_cost_jpy: cost, photo: { ape_median: ape } }) as unknown as ArmMetrics
    const rows = pareto('photo', [fake('sonnet-4-6-prod', 0.1, 2), fake('haiku-5-5-low', 0.12, 0.1), fake('haiku-5-5-medium', 0.15, 0.2), fake('sonnet-5-5-low', 0.1, 3)])
    assert.deepEqual(rows.filter((r) => r.on_frontier).map((r) => r.arm), ['sonnet-4-6-prod', 'haiku-5-5-low'])
    const xs = [0.1, -0.2, 0.05, 0.3, 0, 0.12, -0.01]
    const a = bootstrapCI(xs, median, { seed: 7 })!
    const b = bootstrapCI(xs, median, { seed: 7 })!
    assert.deepEqual(a, b)
    assert.ok(a.lo <= a.estimate && a.estimate <= a.hi)
  })
  await test('describeError: SDK の型付きエラーを分類', () => {
    assert.equal(describeError(new Anthropic.APIConnectionTimeoutError()).type, 'timeout')
    assert.equal(describeError(new Anthropic.APIConnectionError({ message: 'x' })).type, 'connection')
    const rl = describeError(Anthropic.APIError.generate(429, { type: 'error', error: { type: 'rate_limit_error', message: 'slow down' } }, undefined, new Headers()))
    assert.deepEqual([rl.type, rl.status], ['rate_limit_error', 429])
    assert.equal(describeError(new Error('boom')).type, 'internal')
  })

  console.log('== CLI（オフライン） ==')
  const envNoKey = { ...process.env }
  delete envNoKey.ANTHROPIC_API_KEY
  const runCli = (args: string[]) =>
    spawnSync(process.execPath, [...process.execArgv, path.join(EVAL_ROOT, 'src', 'run.ts'), ...args], { cwd: EVAL_ROOT, env: envNoKey, encoding: 'utf8', timeout: 120_000 })
  await test('見積りモードがフィクスチャでキー無しに完走し、生成 API を呼ばない', () => {
    const r = runCli(['--estimate', '--dataset', PHOTO_FIX, '--dataset', SHOT_FIX])
    assert.equal(r.status, 0, r.stderr + r.stdout)
    for (const frag of ['【概算】', 'sonnet-4-6-prod', 'haiku-5-5-medium', '合計', 'OK: haiku-5-5', '生成 API は呼んでいません']) assert.ok(r.stdout.includes(frag), `出力に「${frag}」: ${r.stdout}`)
  })
  await test('--yes でもキーが無ければ明確なメッセージで exit 1、何も書かない', () => {
    const out = path.join(tmpRoot, 'should-not-exist')
    const r = runCli(['--yes', '--dataset', PHOTO_FIX, '--out', out])
    assert.equal(r.status, 1)
    assert.ok(r.stdout.includes('ANTHROPIC_API_KEY が設定されていません'), r.stdout)
    assert.ok(!existsSync(out))
  })

  console.log('== 実行パイプライン（偽 API・ネットワーク不使用） ==')
  // モック用データセット: フィクスチャ画像に SCN マーカー付き content
  const mockPhotos = path.join(tmpRoot, 'mock-photos')
  const mockShots = path.join(tmpRoot, 'mock-shots')
  cpSync(path.join(PHOTO_FIX, 'images'), path.join(mockPhotos, 'images'), { recursive: true })
  cpSync(path.join(SHOT_FIX, 'images'), path.join(mockShots, 'images'), { recursive: true })
  const mc = (id: string, content: string, is_meal = true, images = ['images/landscape.jpg']) => ({ id, images, meal_type: 'lunch' as const, content, expected: { is_meal, totals: is_meal ? tot([600, 25, 19, 75]) : null }, tags: [] })
  writeFileSync(path.join(mockPhotos, 'cases.json'), JSON.stringify({ dataset: 'mock-photos', input_kind: 'photo', description: 'selftest mock', source: 'selftest', preprocessing: 'n/a', cases: [mc('m-ok', ''), mc('m-fenced', 'SCN:fenced'), mc('m-refusal', 'SCN:refusal'), mc('m-maxtok', 'SCN:maxtok'), mc('m-err400', 'SCN:err400', true, ['images/landscape.jpg', 'images/portrait.jpg', 'images/square.jpg']), mc('m-notmeal', 'SCN:empty', false)] } satisfies DatasetFile))
  writeFileSync(path.join(mockShots, 'cases.json'), JSON.stringify({ dataset: 'mock-shots', input_kind: 'screenshot', description: 'selftest mock', source: 'selftest', preprocessing: 'n/a', cases: [{ id: 's-ok', images: ['images/app-a.jpg'], meal_type: 'lunch', content: '', expected: { is_meal: true, totals: tot([712, 31, 24, 93]), expect_warning: false, app_name: 'あすけん' }, tags: [] }, { id: 's-warn', images: ['images/app-a.jpg', 'images/app-b.jpg'], meal_type: 'dinner', content: 'SCN:warn', expected: { is_meal: true, totals: tot([712, 31, 24, 93]), expect_warning: true }, tags: [] }] } satisfies DatasetFile))
  const mockOut = path.join(tmpRoot, 'mock-run')
  const captured: Captured[] = []
  let fail400 = true
  const makeClient = () => new Anthropic({ apiKey: 'offline-mock-key', baseURL: 'https://mock.invalid', fetch: makeMockFetch(captured, { get fail400() { return fail400 } }), maxRetries: 0 })
  const quiet = { log: () => {}, env: { ANTHROPIC_API_KEY: 'offline-mock-key' }, makeClient, mock: true }

  await test('--estimate（キーあり扱い）は countTokens のみ呼び、生成は呼ばない', async () => {
    const lines: string[] = []
    const code = await runMain(['--estimate', '--dataset', mockPhotos, '--arms', 'sonnet-4-6-prod,haiku-5-5-low', '--trials', '1'], { ...quiet, log: (s) => lines.push(s) })
    assert.equal(code, 0)
    assert.ok(captured.length === 12 && captured.every((c) => c.url.endsWith('/v1/messages/count_tokens')), `count_tokens のみ: ${captured.map((c) => c.url).join(',')}`)
    assert.ok(lines.some((l) => l.includes('countTokens による実数')))
    const ct = captured[1].body
    assert.ok(!('max_tokens' in ct) && !('temperature' in ct), 'count_tokens に生成パラメータを送らない')
    assert.deepEqual(ct.output_config, { effort: 'low' })
    captured.length = 0
  })
  await test('モック実行: raw.jsonl・meta.json・summary.json・report.md、refusal/max_tokens/400 を記録し落ちない', async () => {
    const code = await runMain(['--yes', '--dataset', mockPhotos, '--dataset', mockShots, '--trials', '2', '--concurrency', '3', '--out', mockOut], quiet)
    assert.equal(code, 0)
    const lines = readFileSync(path.join(mockOut, 'raw.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l) as RawRecord)
    assert.equal(lines.length, 8 * 4 * 2)
    const get = (cid: string, arm: ArmId, t = 1) => lines.find((r) => r.case_id === cid && r.arm === arm && r.trial === t)!
    assert.equal(get('m-ok', 'haiku-5-5-medium').outcome, 'ok', 'thinking 先頭でも text を拾う')
    assert.equal(get('m-ok', 'sonnet-4-6-prod').parsed?.totals.calories, 600, 'totals は foods から再計算')
    assert.equal(get('m-fenced', 'haiku-5-5-low').outcome, 'ok')
    const rf = get('m-refusal', 'sonnet-5-5-low')
    assert.deepEqual([rf.outcome, rf.stop_reason, rf.stop_details?.category], ['refusal', 'refusal', 'general_harms'])
    const mt = get('m-maxtok', 'haiku-5-5-low')
    assert.deepEqual([mt.outcome, mt.stop_reason, mt.parse_error], ['parse_fail', 'max_tokens', 'No text in Claude response'])
    const er = get('m-err400', 'haiku-5-5-medium')
    assert.deepEqual([er.outcome, er.error?.type, er.error?.status, er.cost_usd], ['error', 'invalid_request_error', 400, null])
    assert.equal(get('m-notmeal', 'sonnet-4-6-prod').outcome, 'empty')
    const so = get('s-ok', 'haiku-5-5-low')
    assert.deepEqual([so.outcome, so.app_name, so.warning, so.parsed?.totals.protein_g], ['ok', 'あすけん', null, 31], 'スクショは totals を信頼')
    assert.equal(get('s-warn', 'sonnet-4-6-prod').warning, '合計が噛み合いません')
    const hk = get('m-ok', 'haiku-5-5-low')
    assert.equal(hk.price_card, 'haiku-5-5:<=100K')
    near(hk.cost_usd, (1500 * 0.1 + 600 * 0.01 + 300 * 0.5) / 1e6, 1e-15)
    assert.equal(hk.attempts, 1)
    assert.equal(typeof hk.latency_ms, 'number')
    assert.equal(hk.prod_timeout_exceeded, false)
    assert.ok(hk.request_id?.startsWith('req_mock_'))
    assert.equal((hk.usage as { cache_read_input_tokens: number }).cache_read_input_tokens, 600)
    // 送ったリクエストの形
    const gens = captured.filter((c) => c.url.endsWith('/v1/messages'))
    assert.equal(gens.length, 64)
    for (const c of gens) {
      const b = c.body
      assert.ok(!('fallbacks' in b) && !('thinking' in b) && !('top_p' in b) && !('top_k' in b))
      assert.ok(!c.headers['anthropic-beta'], 'beta ヘッダーなし')
      const content = (b.messages as Array<{ content: Array<{ type: string; source?: { type: string; media_type: string } }> }>)[0].content
      assert.equal(content.at(-1)!.type, 'text')
      assert.ok(content.slice(0, -1).every((x) => x.type === 'image' && x.source?.type === 'base64' && x.source.media_type === 'image/jpeg'))
      assert.deepEqual((b.system as Array<{ cache_control: unknown }>)[0].cache_control, { type: 'ephemeral' })
      if (b.model === 'claude-sonnet-4-6') assert.deepEqual([b.temperature, b.max_tokens, b.output_config], [0.2, 1024, undefined])
      else assert.ok(!('temperature' in b) && b.max_tokens === 4096 && (b.output_config as { effort: string }).effort)
    }
    const meta = JSON.parse(readFileSync(path.join(mockOut, 'meta.json'), 'utf8')) as RunMeta
    assert.equal(meta.mock, true)
    assert.match(meta.prompts.sha256_photo, /^[0-9a-f]{64}$/)
    assert.ok(meta.finished_at)
    assert.deepEqual(meta.counts, { planned: 64, skipped_existing: 0, executed: 64, errors: 2 })
    const summary = JSON.parse(readFileSync(path.join(mockOut, 'summary.json'), 'utf8')) as { mock: boolean; datasets: Array<{ comparisons: Array<{ decision: { verdict: string } }> }> }
    assert.equal(summary.mock, true)
    assert.ok(summary.datasets.every((d) => d.comparisons.every((c) => c.decision.verdict === 'INSUFFICIENT DATA')))
    const report = readFileSync(path.join(mockOut, 'report.md'), 'utf8')
    assert.ok(report.includes('実測結果ではありません'))
    assert.ok(report.includes('判定サマリー') && report.includes('パレート'))
  })
  await test('--resume: 記録済みはスキップ、--retry-errors で API エラーのみ再実行', async () => {
    captured.length = 0
    assert.equal(await runMain(['--yes', '--resume', mockOut], quiet), 0)
    assert.equal(captured.length, 0, '全件記録済みなので呼ばない')
    fail400 = false
    assert.equal(await runMain(['--yes', '--resume', mockOut, '--retry-errors'], quiet), 0)
    assert.equal(captured.length, 2)
    const lines = readFileSync(path.join(mockOut, 'raw.jsonl'), 'utf8').trim().split('\n')
    assert.equal(lines.length, 66)
    const summary = JSON.parse(readFileSync(path.join(mockOut, 'summary.json'), 'utf8')) as { n_records: number; datasets: Array<{ arms: Array<{ arm: string; error: { num: number } }> }> }
    assert.equal(summary.n_records, 64)
    assert.equal(summary.datasets[0].arms.find((a) => a.arm === 'haiku-5-5-medium')!.error.num, 0)
    await assert.rejects(runMain(['--yes', '--resume', mockOut, '--arms', 'haiku-5-5-low'], quiet), /--resume/)
  })
  await test('レポートはモック実行に「実測ではない」警告を必ず出す', () => {
    const md = renderReport(gradeRun(fakeMeta(['sonnet-4-6-prod']), [], []), fakeMeta(['sonnet-4-6-prod']))
    assert.ok(md.includes('実測結果ではありません'))
  })
}

run()
  .catch((e) => {
    results.push({ name: 'selftest 本体', ok: false, err: e })
    console.error(e)
  })
  .finally(() => {
    rmSync(tmpRoot, { recursive: true, force: true })
    const failed = results.filter((r) => !r.ok)
    console.log(`\n${results.length - failed.length}/${results.length} passed`)
    process.exit(failed.length ? 1 : 0)
  })
