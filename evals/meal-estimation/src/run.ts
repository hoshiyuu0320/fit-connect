/**
 * A/B 実行 CLI。
 *
 *   npm run estimate                                   # 見積りのみ（API キーがあれば countTokens で入力トークンを実測）
 *   ANTHROPIC_API_KEY=... npm run run -- --yes         # 実行（--yes が無ければ見積りを出して終了）
 *
 * オプション:
 *   --dataset <dir>   繰り返し可。既定: datasets/*\/cases.json すべて
 *   --arms a,b        既定: 全 4 アーム
 *   --trials N        既定 3
 *   --limit N         データセットごとのケース数上限（先頭から）
 *   --concurrency N   既定 4
 *   --out <dir>       既定 runs/<UTC タイムスタンプ>
 *   --resume <dir>    raw.jsonl にある (case, arm, trial) をスキップして続きから
 *   --retry-errors    --resume 時、API エラーで終わった (case, arm, trial) は再実行する
 *   --estimate        キーがあれば countTokens で入力トークンを実測して見積る
 *   --yes             実際に生成 API を呼ぶ（無ければ見積りだけ表示して exit 0）
 */
import Anthropic, { type Middleware } from '@anthropic-ai/sdk'
import { execFileSync } from 'node:child_process'
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import path from 'node:path'
import { pathToFileURL } from 'node:url'
import { parseArgs } from 'node:util'
import {
  ALL_ARM_IDS,
  ARMS,
  BASELINE_ARM_ID,
  costFromUsage,
  estimateCostUsd,
  estimatedOutputTokens,
  getArm,
  HAIKU_55_LONG_PROMPT_THRESHOLD,
  JPY_PER_USD,
  TEXT_TOKENS_PER_CHAR,
  visualTokensFor,
  type ArmConfig,
  type ArmId,
} from './arms.js'
import { discoverDatasets, loadDataset, readCaseImages, snapshotDataset, type Case, type CaseImages, type LoadedDataset } from './dataset.js'
import { buildRequestParams, buildUserText, processResponse, selectSystemPrompt } from './production-logic.js'
import { EVAL_ROOT, loadProductionPrompts, PRODUCTION_INDEX_PATH, REPO_ROOT, type ProductionPrompts } from './prompts.js'
import { generateReport, printVerdicts } from './report.js'
import type { RawRecord, RecordedError, RunMeta, SerializableArgs } from './run-types.js'

export const REQUEST_TIMEOUT_MS = 60_000
export const MAX_RETRIES = 3

// ---------------------------------------------------------------------------
// 引数
// ---------------------------------------------------------------------------

export interface CliArgs {
  datasets: string[]
  arms: ArmId[]
  trials: number
  limit: number | null
  concurrency: number
  out: string | null
  resume: string | null
  estimate: boolean
  yes: boolean
  retryErrors: boolean
  /** 明示指定されたか（--resume との整合チェック用） */
  explicit: { datasets: boolean; arms: boolean; limit: boolean; trials: boolean }
}

function posInt(name: string, v: string | undefined, def: number | null): number | null {
  if (v === undefined) return def
  const n = Number(v)
  if (!Number.isInteger(n) || n < 1) throw new Error(`--${name} は 1 以上の整数で指定してください（${v}）`)
  return n
}

export function parseCliArgs(argv: string[]): CliArgs {
  const { values } = parseArgs({
    args: argv,
    strict: true,
    allowPositionals: false,
    options: {
      dataset: { type: 'string', multiple: true },
      arms: { type: 'string' },
      trials: { type: 'string' },
      limit: { type: 'string' },
      concurrency: { type: 'string' },
      out: { type: 'string' },
      resume: { type: 'string' },
      estimate: { type: 'boolean', default: false },
      yes: { type: 'boolean', default: false },
      'retry-errors': { type: 'boolean', default: false },
    },
  })
  const arms = values.arms
    ? values.arms.split(',').map((s) => s.trim()).filter(Boolean).map((s) => getArm(s).id)
    : ALL_ARM_IDS.slice()
  if (new Set(arms).size !== arms.length) throw new Error('--arms に重複があります')
  const concurrency = posInt('concurrency', values.concurrency, 4) as number
  if (concurrency > 32) throw new Error('--concurrency は 32 以下にしてください')
  if (values.resume && values.out) throw new Error('--resume と --out は同時に指定できません（--resume のディレクトリに追記します）')
  return {
    datasets: values.dataset ?? [],
    arms,
    trials: posInt('trials', values.trials, 3) as number,
    limit: posInt('limit', values.limit, null),
    concurrency,
    out: values.out ?? null,
    resume: values.resume ?? null,
    estimate: values.estimate ?? false,
    yes: values.yes ?? false,
    retryErrors: values['retry-errors'] ?? false,
    explicit: {
      datasets: values.dataset !== undefined,
      arms: values.arms !== undefined,
      limit: values.limit !== undefined,
      trials: values.trials !== undefined,
    },
  }
}

// ---------------------------------------------------------------------------
// 計画
// ---------------------------------------------------------------------------

export interface PlannedCase {
  ds: LoadedDataset
  c: Case
  images: CaseImages
}
export interface Job {
  pc: PlannedCase
  arm: ArmConfig
  trial: number
  key: string
}

export function recordKey(dataset: string, caseId: string, arm: string, trial: number): string {
  return `${dataset}::${caseId}::${arm}::${trial}`
}

/** case → trial → arm の順に並べる（同じケース・試行のアームを隣接させ、時間帯の偏りを避ける） */
export function planJobs(cases: PlannedCase[], arms: ArmConfig[], trials: number): Job[] {
  const jobs: Job[] = []
  for (const pc of cases) {
    for (let t = 1; t <= trials; t++) {
      for (const arm of arms) jobs.push({ pc, arm, trial: t, key: recordKey(pc.ds.name, pc.c.id, arm.id, t) })
    }
  }
  return jobs
}

// ---------------------------------------------------------------------------
// 見積り
// ---------------------------------------------------------------------------

export interface UnitEstimate {
  arm: ArmId
  dataset: string
  case_id: string
  prompt_tokens: number
  output_tokens: number
  source: 'count_tokens' | 'local'
}

/** ローカル概算: 画像はティア規則の visual token、テキストは文字数 × 係数 */
export function localPromptTokens(arm: ArmConfig, systemPrompt: string, userText: string, dims: CaseImages['dims']): number {
  const chars = [...systemPrompt].length + [...userText].length
  const text = Math.ceil(chars * TEXT_TOKENS_PER_CHAR[arm.tokenizer])
  const visual = dims.reduce((s, d) => s + visualTokensFor(d.width, d.height, arm.vision_tier).tokens, 0)
  return text + visual
}

/** 端末表示幅（全角 = 2）。見積り表の桁揃え用 */
function displayWidth(s: string): number {
  let w = 0
  for (const ch of s) {
    const c = ch.codePointAt(0) as number
    const wide =
      (c >= 0x1100 && c <= 0x115f) || (c >= 0x2e80 && c <= 0xa4cf) || (c >= 0xac00 && c <= 0xd7a3) ||
      (c >= 0xf900 && c <= 0xfaff) || (c >= 0xfe30 && c <= 0xfe4f) || (c >= 0xff00 && c <= 0xff60) || (c >= 0xffe0 && c <= 0xffe6)
    w += wide ? 2 : 1
  }
  return w
}

export interface EstimateResult {
  units: UnitEstimate[]
  lines: string[]
  total_usd: number
  haiku_ok: boolean
  mode: 'count_tokens' | 'local'
}

export async function estimate(
  jobs: Job[],
  prompts: ProductionPrompts,
  client: Anthropic | null,
  log: (s: string) => void,
): Promise<EstimateResult> {
  // (case, arm) 単位でトークンを求め、試行回数ぶん掛ける
  const unitKey = (j: Job) => `${j.pc.ds.name}::${j.pc.c.id}::${j.arm.id}`
  const unitJobs = new Map<string, { job: Job; count: number }>()
  for (const j of jobs) {
    const u = unitJobs.get(unitKey(j))
    if (u) u.count++
    else unitJobs.set(unitKey(j), { job: j, count: 1 })
  }
  let mode: 'count_tokens' | 'local' = client ? 'count_tokens' : 'local'
  const units: Array<UnitEstimate & { count: number }> = []
  for (const { job, count } of unitJobs.values()) {
    const sys = selectSystemPrompt(job.pc.ds.input_kind, prompts)
    let promptTokens: number | null = null
    if (mode === 'count_tokens' && client) {
      const p = buildRequestParams(job.arm, sys, job.pc.images.base64, job.pc.c.meal_type, job.pc.c.content)
      try {
        const r = await client.messages.countTokens({
          model: p.model,
          system: p.system,
          messages: p.messages,
          ...(p.output_config ? { output_config: p.output_config } : {}),
        })
        promptTokens = r.input_tokens
      } catch (e) {
        log(`⚠ countTokens に失敗したためローカル概算に切り替えます: ${describeError(e).type} ${describeError(e).message}`)
        mode = 'local'
      }
    }
    if (promptTokens === null) {
      promptTokens = localPromptTokens(job.arm, sys, buildUserText(job.pc.c.meal_type, job.pc.c.content), job.pc.images.dims)
    }
    units.push({
      arm: job.arm.id,
      dataset: job.pc.ds.name,
      case_id: job.pc.c.id,
      prompt_tokens: promptTokens,
      output_tokens: estimatedOutputTokens(job.arm),
      source: mode,
      count,
    })
  }
  // count_tokens の途中で失敗した場合、全体をローカル概算で揃え直す
  if (mode === 'local' && units.some((u) => u.source === 'count_tokens')) {
    for (const u of units) {
      if (u.source === 'local') continue
      const job = unitJobs.get(`${u.dataset}::${u.case_id}::${u.arm}`)!.job
      u.prompt_tokens = localPromptTokens(job.arm, selectSystemPrompt(job.pc.ds.input_kind, prompts), buildUserText(job.pc.c.meal_type, job.pc.c.content), job.pc.images.dims)
      u.source = 'local'
    }
  }

  const lines: string[] = []
  lines.push(
    mode === 'count_tokens'
      ? '== コスト見積り（入力トークン: countTokens による実数 / 出力トークン: 仮定値 / キャッシュ無しとして計算） =='
      : '== コスト見積り【概算】（入力: ローカル近似 = 画像はティア規則の visual token、テキストは 文字数×0.9（sonnet-4-6）/×1.17（4.7 以降のトークナイザ）。出力: 仮定値。キャッシュ無し） ==',
  )
  lines.push(`出力トークンの仮定: 可視 JSON 400 + thinking（effort low 500 / medium 1500、sonnet-4-6 は thinking なし）`)
  lines.push(`為替: 1 USD = ${JPY_PER_USD} 円`)
  lines.push('')
  const header = ['arm', 'calls', 'prompt tok(平均)', 'prompt tok(最大)', 'output tok(仮定)', 'USD', 'JPY', '円/回']
  const rows: string[][] = []
  let totalUsd = 0
  let totalCalls = 0
  let haikuOk = true
  let haikuMax = 0
  const armIds = [...new Set(units.map((u) => u.arm))]
  for (const armId of armIds) {
    const us = units.filter((u) => u.arm === armId)
    const arm = ARMS[armId]
    const calls = us.reduce((s, u) => s + u.count, 0)
    let usd = 0
    let tokSum = 0
    let tokMax = 0
    for (const u of us) {
      const c = estimateCostUsd(arm.model, u.prompt_tokens, u.output_tokens)
      usd += c.cost_usd * u.count
      tokSum += u.prompt_tokens * u.count
      tokMax = Math.max(tokMax, u.prompt_tokens)
      if (arm.model === 'claude-haiku-5-5') {
        haikuMax = Math.max(haikuMax, u.prompt_tokens)
        if (u.prompt_tokens > HAIKU_55_LONG_PROMPT_THRESHOLD) haikuOk = false
      }
    }
    totalUsd += usd
    totalCalls += calls
    rows.push([
      armId,
      String(calls),
      calls ? Math.round(tokSum / calls).toLocaleString('en-US') : '0',
      tokMax.toLocaleString('en-US'),
      String(estimatedOutputTokens(arm)),
      `$${usd.toFixed(4)}`,
      `${(usd * JPY_PER_USD).toFixed(1)}円`,
      calls ? `${((usd * JPY_PER_USD) / calls).toFixed(3)}円` : '-',
    ])
  }
  rows.push(['合計', String(totalCalls), '', '', '', `$${totalUsd.toFixed(4)}`, `${(totalUsd * JPY_PER_USD).toFixed(1)}円`, ''])
  const widths = header.map((h, i) => Math.max(displayWidth(h), ...rows.map((r) => displayWidth(r[i]))))
  const fmt = (r: string[]) => r.map((c, i) => c + ' '.repeat(widths[i] - displayWidth(c))).join('  ')
  lines.push(fmt(header))
  lines.push(widths.map((w) => '-'.repeat(w)).join('  '))
  for (const r of rows) lines.push(fmt(r))
  lines.push('')
  if (armIds.some((a) => ARMS[a].model === 'claude-haiku-5-5')) {
    lines.push(
      haikuOk
        ? `OK: haiku-5-5 の全プロンプトが ${HAIKU_55_LONG_PROMPT_THRESHOLD.toLocaleString('en-US')} トークン以下（最大 ${haikuMax.toLocaleString('en-US')}${mode === 'local' ? '、概算' : ''}）→ 通常レートカード`
        : `NG: haiku-5-5 のプロンプトに ${HAIKU_55_LONG_PROMPT_THRESHOLD.toLocaleString('en-US')} トークン超があります（最大 ${haikuMax.toLocaleString('en-US')}）→ 高額カードになるため中止`,
    )
  }
  return { units, lines, total_usd: totalUsd, haiku_ok: haikuOk, mode }
}

// ---------------------------------------------------------------------------
// 実行
// ---------------------------------------------------------------------------

/** SDK の型付きエラーを記録用に要約する（具体的なクラスから順に判定） */
export function describeError(e: unknown): RecordedError {
  if (e instanceof Anthropic.APIConnectionTimeoutError) return { type: 'timeout', status: null, message: e.message }
  if (e instanceof Anthropic.APIUserAbortError) return { type: 'aborted', status: null, message: e.message }
  if (e instanceof Anthropic.APIConnectionError) return { type: 'connection', status: null, message: e.message }
  if (e instanceof Anthropic.APIError) {
    return { type: e.type ?? e.constructor.name, status: typeof e.status === 'number' ? e.status : null, message: e.message }
  }
  return { type: 'internal', status: null, message: e instanceof Error ? e.message : String(e) }
}

export async function runJob(client: Anthropic, job: Job, prompts: ProductionPrompts): Promise<RawRecord> {
  const { pc, arm, trial } = job
  const kind = pc.ds.input_kind
  const params = buildRequestParams(arm, selectSystemPrompt(kind, prompts), pc.images.base64, pc.c.meal_type, pc.c.content)
  const attemptStarts: number[] = []
  const timing: Middleware = async (request, next) => {
    attemptStarts.push(Date.now())
    return next(request)
  }
  const startedAt = new Date()
  const t0 = Date.now()
  const base = {
    key: job.key,
    case_id: pc.c.id,
    dataset: pc.ds.name,
    input_kind: kind,
    arm: arm.id,
    model: arm.model,
    trial,
    started_at: startedAt.toISOString(),
  }
  try {
    const { data: msg, request_id } = await client.messages
      .create(params, { timeout: REQUEST_TIMEOUT_MS, middleware: [timing] })
      .withResponse()
    const tEnd = Date.now()
    const latency = tEnd - (attemptStarts.at(-1) ?? t0)
    const processed = processResponse(msg, kind)
    const cost = costFromUsage(arm.model, msg.usage)
    return {
      ...base,
      latency_ms: latency,
      total_ms: tEnd - t0,
      attempts: attemptStarts.length,
      stop_reason: msg.stop_reason,
      stop_details: msg.stop_details ? { category: msg.stop_details.category, explanation: msg.stop_details.explanation } : null,
      response_model: msg.model,
      request_id: request_id ?? null,
      usage: msg.usage as unknown as Record<string, unknown>,
      price_card: cost.price_card,
      prompt_tokens: cost.prompt_tokens,
      cost_usd: cost.cost_usd,
      ...processed,
      error: null,
      prod_timeout_exceeded: latency > 30_000,
    }
  } catch (e) {
    const tEnd = Date.now()
    const latency = attemptStarts.length ? tEnd - (attemptStarts.at(-1) as number) : null
    return {
      ...base,
      latency_ms: latency,
      total_ms: tEnd - t0,
      attempts: attemptStarts.length,
      stop_reason: null,
      stop_details: null,
      response_model: null,
      request_id: e instanceof Anthropic.APIError ? (e.requestID ?? null) : null,
      usage: null,
      price_card: null,
      prompt_tokens: null,
      cost_usd: null,
      raw_text: null,
      parsed: null,
      parse_error: null,
      app_name: null,
      warning: null,
      empty_result: null,
      outcome: 'error',
      error: describeError(e),
      prod_timeout_exceeded: latency === null ? null : latency > 30_000,
    }
  }
}

async function pool<T>(items: T[], concurrency: number, fn: (item: T, index: number) => Promise<void>): Promise<void> {
  let next = 0
  const workers = Array.from({ length: Math.min(concurrency, items.length) }, async () => {
    while (next < items.length) {
      const i = next++
      await fn(items[i], i)
    }
  })
  await Promise.all(workers)
}

function utcStamp(d = new Date()): string {
  return d.toISOString().replace(/\.\d+Z$/, 'Z').replace(/:/g, '-')
}

function gitInfo(): RunMeta['git'] {
  try {
    const head = execFileSync('git', ['-C', REPO_ROOT, 'rev-parse', 'HEAD'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim()
    let dirty: boolean | null = null
    try {
      const out = execFileSync('git', ['-C', REPO_ROOT, 'status', '--porcelain', '--', path.relative(REPO_ROOT, PRODUCTION_INDEX_PATH)], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] })
      dirty = out.trim().length > 0
    } catch {
      dirty = null
    }
    return { head, production_file_dirty: dirty }
  } catch {
    return { head: null, production_file_dirty: null }
  }
}

function sdkVersion(): string | null {
  try {
    const p = path.join(EVAL_ROOT, 'node_modules', '@anthropic-ai', 'sdk', 'package.json')
    return (JSON.parse(readFileSync(p, 'utf8')) as { version?: string }).version ?? null
  } catch {
    return null
  }
}

function requestShape(arm: ArmConfig): Record<string, unknown> {
  return {
    model: arm.model,
    max_tokens: arm.max_tokens,
    ...(arm.temperature !== undefined ? { temperature: arm.temperature } : {}),
    ...(arm.effort !== undefined ? { output_config: { effort: arm.effort } } : {}),
    system: '[{type:text, text:<production prompt>, cache_control:{type:ephemeral}}]',
    messages: '[{role:user, content:[image(base64 image/jpeg) x1..3, text]}]',
  }
}

export interface RunDeps {
  env: Record<string, string | undefined>
  log: (s: string) => void
  /** テスト用: クライアント生成を差し替える（モック fetch 等）。未指定なら new Anthropic() */
  makeClient?: () => Anthropic
  /** テスト用: meta.mock = true（レポートに「実測ではない」と明示） */
  mock?: boolean
}

function toSerializable(a: CliArgs, out: string): SerializableArgs {
  return {
    datasets: a.datasets,
    arms: a.arms,
    trials: a.trials,
    limit: a.limit,
    concurrency: a.concurrency,
    out,
    resume: a.resume,
    estimate: a.estimate,
    yes: a.yes,
    retry_errors: a.retryErrors,
  }
}

/** CLI 本体。終了コードを返す（process.exit はしない） */
export async function main(argv: string[], partialDeps: Partial<RunDeps> = {}): Promise<number> {
  const deps: RunDeps = { env: process.env, log: (s) => console.log(s), ...partialDeps }
  const { log } = deps
  const args = parseCliArgs(argv)
  const hasKey = typeof deps.env.ANTHROPIC_API_KEY === 'string' && deps.env.ANTHROPIC_API_KEY.length > 0
  const makeClient = deps.makeClient ?? (() => new Anthropic({ maxRetries: MAX_RETRIES, timeout: REQUEST_TIMEOUT_MS }))

  // --resume: 元の実行設定を引き継ぐ
  let resumeMeta: RunMeta | null = null
  if (args.resume) {
    const mp = path.join(args.resume, 'meta.json')
    if (!existsSync(mp)) throw new Error(`--resume 先に meta.json がありません: ${args.resume}`)
    resumeMeta = JSON.parse(readFileSync(mp, 'utf8')) as RunMeta
    if (args.explicit.datasets || args.explicit.arms || args.explicit.limit) {
      throw new Error('--resume では --dataset / --arms / --limit は元の meta.json の値を使います（指定しないでください）。--trials は増やせます')
    }
    args.datasets = resumeMeta.args.datasets
    args.arms = resumeMeta.args.arms
    args.limit = resumeMeta.args.limit
    if (!args.explicit.trials) args.trials = resumeMeta.args.trials
    else if (args.trials < resumeMeta.args.trials) throw new Error(`--trials は元の ${resumeMeta.args.trials} 以上にしてください`)
  }

  const prompts = loadProductionPrompts()
  if (resumeMeta && (resumeMeta.prompts.sha256_photo !== prompts.sha256.photo || resumeMeta.prompts.sha256_screenshot !== prompts.sha256.screenshot)) {
    throw new Error('本番プロンプトが元の実行から変わっています。混ぜると比較が無効になるため、新しい --out で実行し直してください')
  }

  const datasetDirs = args.datasets.length ? args.datasets : discoverDatasets()
  if (datasetDirs.length === 0) {
    log('データセットがありません。datasets/<name>/cases.json を用意するか --dataset で指定してください（README 参照）')
    return 1
  }
  const loaded = datasetDirs.map((d) => loadDataset(d))
  const names = loaded.map((d) => d.name)
  if (new Set(names).size !== names.length) throw new Error(`dataset 名が重複しています: ${names.join(', ')}`)
  if (resumeMeta) {
    for (const ds of loaded) {
      const prev = resumeMeta.datasets.find((d) => d.name === ds.name)
      if (prev && prev.sha256 !== ds.sha256) throw new Error(`データセット ${ds.name} の cases.json が元の実行から変わっています`)
    }
  }

  const arms = args.arms.map((id) => ARMS[id])
  const planned: PlannedCase[] = []
  for (const ds of loaded) {
    const cases = args.limit ? ds.file.cases.slice(0, args.limit) : ds.file.cases
    for (const c of cases) planned.push({ ds, c, images: await readCaseImages(ds, c) })
  }
  const allJobs = planJobs(planned, arms, args.trials)

  // 既存記録のスキップ
  const outDir = args.resume ?? args.out ?? path.join(EVAL_ROOT, 'runs', utcStamp())
  const rawPath = path.join(outDir, 'raw.jsonl')
  const done = new Set<string>()
  if (args.resume && existsSync(rawPath)) {
    const last = new Map<string, RawRecord>()
    for (const line of readFileSync(rawPath, 'utf8').split('\n')) {
      if (!line.trim()) continue
      try {
        const r = JSON.parse(line) as RawRecord
        last.set(r.key, r)
      } catch {
        /* 書きかけ行は無視 */
      }
    }
    for (const [k, r] of last) if (!(args.retryErrors && r.outcome === 'error')) done.add(k)
  }
  const jobs = allJobs.filter((j) => !done.has(j.key))

  log(`データセット: ${loaded.map((d) => `${d.name}(${d.input_kind}, ${planned.filter((p) => p.ds === d).length}件)`).join(', ')}`)
  log(`アーム: ${args.arms.join(', ')} / 試行 ${args.trials} / 呼び出し予定 ${jobs.length}${done.size ? `（既存 ${allJobs.length - jobs.length} 件をスキップ）` : ''}`)
  log('')

  // 見積り（--estimate かつキーあり → countTokens、それ以外はローカル概算）
  const estClient = args.estimate && hasKey ? makeClient() : null
  if (args.estimate && !hasKey) log('ANTHROPIC_API_KEY が未設定のため、ローカル概算で見積ります。')
  const est = await estimate(jobs, prompts, estClient, log)
  for (const l of est.lines) log(l)
  if (!est.haiku_ok) return 1

  if (!args.yes) {
    log('')
    log('（生成 API は呼んでいません）実行するには --yes を付けてください: ANTHROPIC_API_KEY=... npm run run -- --yes')
    return 0
  }
  if (!hasKey) {
    log('')
    log('エラー: --yes が指定されましたが ANTHROPIC_API_KEY が設定されていません。キーを環境変数で渡してください（.env は読みません）。')
    return 1
  }
  if (jobs.length === 0) {
    log('実行すべき呼び出しはありません。')
  }

  // 実行
  mkdirSync(outDir, { recursive: true })
  const metaPath = path.join(outDir, 'meta.json')
  const nowIso = new Date().toISOString()
  const meta: RunMeta = resumeMeta
    ? { ...resumeMeta, args: { ...resumeMeta.args, trials: args.trials, concurrency: args.concurrency }, resumed_at: [...resumeMeta.resumed_at, nowIso], finished_at: null }
    : {
        schema_version: 1,
        mock: deps.mock ?? false,
        args: toSerializable(args, path.relative(EVAL_ROOT, outDir)),
        arms: arms.map((a) => ({ ...a, request_shape: requestShape(a) })),
        baseline_arm: BASELINE_ARM_ID,
        prompts: {
          source_path: path.relative(REPO_ROOT, prompts.source_path),
          sha256_photo: prompts.sha256.photo,
          sha256_screenshot: prompts.sha256.screenshot,
          sha256_source_file: prompts.sha256.source_file,
        },
        datasets: loaded.map((d) => ({
          name: d.name,
          input_kind: d.input_kind,
          cases_path: path.relative(EVAL_ROOT, d.cases_path),
          sha256: d.sha256,
          n_cases: planned.filter((p) => p.ds === d).length,
        })),
        git: gitInfo(),
        sdk_version: sdkVersion(),
        node_version: process.version,
        jpy_per_usd: JPY_PER_USD,
        started_at: nowIso,
        finished_at: null,
        resumed_at: [],
        counts: null,
        notes: [
          'fallbacks パラメータ（サーバ側フォールバック）はどのアームにも送っていない: refusal を回避せず計測するため',
          '画像は本番の署名 URL と同じバイト列を base64(image/jpeg) で送信',
          `リクエストタイムアウト ${REQUEST_TIMEOUT_MS / 1000}s、SDK maxRetries ${MAX_RETRIES}`,
        ],
      }
  writeFileSync(metaPath, JSON.stringify(meta, null, 2) + '\n')
  writeFileSync(
    path.join(outDir, 'datasets.json'),
    JSON.stringify(loaded.map((d) => snapshotDataset(d, planned.filter((p) => p.ds === d).map((p) => p.c))), null, 2) + '\n',
  )

  const client = makeClient()
  let finished = 0
  let errors = 0
  await pool(jobs, args.concurrency, async (job) => {
    const rec = await runJob(client, job, prompts)
    appendFileSync(rawPath, JSON.stringify(rec) + '\n')
    finished++
    if (rec.outcome === 'error') errors++
    const status = rec.outcome === 'error' ? `ERROR ${rec.error?.type}${rec.error?.status ? ` ${rec.error.status}` : ''}` : rec.outcome
    log(
      `[${finished}/${jobs.length}] ${job.pc.ds.name}/${job.pc.c.id} ${job.arm.id} t${job.trial} ${status}` +
        `${rec.stop_reason && rec.stop_reason !== 'end_turn' ? ` stop=${rec.stop_reason}` : ''}` +
        `${rec.latency_ms !== null ? ` ${(rec.latency_ms / 1000).toFixed(1)}s` : ''}` +
        `${rec.cost_usd !== null ? ` $${rec.cost_usd.toFixed(5)}` : ''}`,
    )
  })

  meta.finished_at = new Date().toISOString()
  const prevCounts = meta.counts ?? { planned: 0, skipped_existing: 0, executed: 0, errors: 0 }
  meta.counts = {
    planned: allJobs.length,
    skipped_existing: allJobs.length - jobs.length,
    executed: prevCounts.executed + jobs.length,
    errors: prevCounts.errors + errors,
  }
  writeFileSync(metaPath, JSON.stringify(meta, null, 2) + '\n')

  const { summaryPath, reportPath, summary } = await generateReport(outDir)
  log('')
  log(`raw    : ${rawPath}`)
  log(`summary: ${summaryPath}`)
  log(`report : ${reportPath}`)
  printVerdicts(summary, log)
  return 0
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main(process.argv.slice(2)).then(
    (code) => process.exit(code),
    (e) => {
      console.error(`エラー: ${(e as Error).message}`)
      process.exit(1)
    },
  )
}
