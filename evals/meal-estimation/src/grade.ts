/**
 * raw.jsonl を採点して summary を作る（純関数 gradeRun + 読み込み補助 loadRunDir）。
 *
 * 定義（report.md の「定義」節にも同じ説明を出す）:
 *   - API エラー（outcome='error'）は「エラー率」以外の分母から除外する（インフラ要因のため）。
 *   - EMPTY 扱い = outcome が 'empty'（foods が空 = 本番 EMPTY_RESULT）または 'refusal'
 *     （feasibility §4-3 で refusal を EMPTY_RESULT に写像する想定）。
 *   - 写真の誤差は outcome='ok' の呼び出しのみで計算（失敗は false-EMPTY 率・パース失敗率で別に見る）。
 *     期待値は totals と alt_totals のうち APE が最小のものを採用。
 *   - スクショの正答は |予測 − 期待| ≤ 1。項目別は totals / alt_totals のどれかと一致すれば正解、
 *     4 項目同時正解は「同じ 1 つの期待値セット」で 4 項目とも一致した場合。ok 以外の呼び出しは不正解。
 *   - ベースライン比較はケース単位（試行平均）で、両アームに値があるケースのみの対応あり比較。
 */
import { existsSync, readFileSync } from 'node:fs'
import path from 'node:path'
import { BASELINE_ARM_ID, JPY_PER_USD, type ArmId } from './arms.js'
import type { DatasetSnapshot, Expected } from './dataset.js'
import type { InputKind, Totals } from './production-logic.js'
import type { RawRecord, RunMeta } from './run-types.js'
import { bootstrapCI, coefficientOfVariation, mean, median, quantile, type BootstrapCI } from './stats.js'

export const PROD_TIMEOUT_MS = 30_000
export const MIN_GRADED_CASES = 20
export const BOOTSTRAP_SEED = 20261009

export interface Rate {
  num: number
  den: number
  value: number | null
}
function rate(num: number, den: number): Rate {
  return { num, den, value: den > 0 ? num / den : null }
}

export interface PhotoMetrics {
  n_calls_graded: number
  ape_median: number | null
  ape_p90: number | null
  ape_mean: number | null
  mae_kcal: number | null
  within20: Rate
  mae_protein_g: number | null
  mae_fat_g: number | null
  mae_carbs_g: number | null
  cv_median: number | null
  n_cases_cv: number
}

export interface ScreenshotMetrics {
  field_correct: Record<keyof Totals, Rate>
  all_four_correct: Rate
  warning_accuracy: Rate
  foods_count_exact: Rate
  app_name_match: Rate
}

export interface ArmMetrics {
  arm: ArmId
  calls: number
  parse_fail: Rate
  refusal: Rate
  max_tokens_stop: Rate
  error: Rate
  false_empty: Rate
  correct_rejection: Rate
  latency_p50_ms: number | null
  latency_p90_ms: number | null
  over_30s: Rate
  mean_cost_usd: number | null
  mean_cost_jpy: number | null
  jpy_per_1000_calls: number | null
  total_cost_usd: number
  price_cards: Record<string, number>
  photo?: PhotoMetrics
  screenshot?: ScreenshotMetrics
}

export type Verdict = 'PASS' | 'FAIL' | 'INSUFFICIENT DATA'
export interface Clause {
  label: string
  pass: boolean | null
  detail: string
}
export interface Decision {
  verdict: Verdict
  clauses: Clause[]
  reasons: string[]
}

export interface AnswerSummary {
  trial: number
  outcome: string
  totals: Totals | null
  warning: string | null
}
export interface WorstCase {
  case_id: string
  expected: Totals | null
  n_alt_totals: number
  expect_warning: boolean | null
  baseline_value: number
  candidate_value: number
  delta: number
  baseline_answers: AnswerSummary[]
  candidate_answers: AnswerSummary[]
}

export interface Comparison {
  candidate: ArmId
  baseline: ArmId
  paired_cases: number
  photo?: { base_median_ape: number | null; cand_median_ape: number | null; delta_ape_median: BootstrapCI | null }
  screenshot?: { base_all4: number | null; cand_all4: number | null; delta_all4_mean: BootstrapCI | null }
  decision: Decision
  worst: WorstCase[]
  /** ベースラインは 1 回以上 ok だが候補は一度も ok でなかったケース（写真）/ 候補の全試行が失敗（スクショ） */
  candidate_failures: Array<{ case_id: string; outcomes: string[] }>
}

export interface ParetoRow {
  arm: ArmId
  score: number | null
  score_label: string
  higher_is_better: boolean
  cost_jpy_per_call: number | null
  on_frontier: boolean
}

export interface DatasetSummary {
  name: string
  input_kind: InputKind
  n_cases: number
  n_graded_cases: number
  arms: ArmMetrics[]
  comparisons: Comparison[]
  pareto: ParetoRow[]
}

export interface Summary {
  run_dir: string
  generated_at: string
  mock: boolean
  baseline_arm: ArmId
  arms: ArmId[]
  jpy_per_usd: number
  n_records: number
  datasets: DatasetSummary[]
}

// ---------------------------------------------------------------------------

export function loadRunDir(runDir: string): { meta: RunMeta; snapshots: DatasetSnapshot[]; records: RawRecord[] } {
  const metaPath = path.join(runDir, 'meta.json')
  const snapPath = path.join(runDir, 'datasets.json')
  const rawPath = path.join(runDir, 'raw.jsonl')
  for (const p of [metaPath, snapPath]) if (!existsSync(p)) throw new Error(`run ディレクトリに ${path.basename(p)} がありません: ${runDir}`)
  const meta = JSON.parse(readFileSync(metaPath, 'utf8')) as RunMeta
  const snapshots = JSON.parse(readFileSync(snapPath, 'utf8')) as DatasetSnapshot[]
  const records: RawRecord[] = []
  if (existsSync(rawPath)) {
    const lines = readFileSync(rawPath, 'utf8').split('\n')
    lines.forEach((line, i) => {
      if (!line.trim()) return
      try {
        records.push(JSON.parse(line) as RawRecord)
      } catch {
        // 中断時の書きかけ行などはスキップ（警告のみ）
        console.warn(`raw.jsonl ${i + 1} 行目を JSON として読めないためスキップ`)
      }
    })
  }
  return { meta, snapshots, records }
}

/** 同じ key の行が複数ある場合（--resume --retry-errors）は最後の行を採用 */
export function dedupeRecords(records: RawRecord[]): RawRecord[] {
  const m = new Map<string, RawRecord>()
  for (const r of records) m.set(r.key, r)
  return [...m.values()]
}

const isNonError = (r: RawRecord) => r.outcome !== 'error'
const isEmptyLike = (r: RawRecord) => r.outcome === 'empty' || r.outcome === 'refusal'

function refsOf(e: Expected): Totals[] {
  if (!e.totals) return []
  return [e.totals, ...(e.alt_totals ?? [])]
}

/** APE が最小になる期待値（calories が 0 の期待値しか無ければ絶対誤差最小） */
function bestRef(pred: Totals, refs: Totals[]): { ref: Totals; ape: number | null } {
  let best: { ref: Totals; ape: number | null; key: number; abs: number } | null = null
  for (const ref of refs) {
    const abs = Math.abs(pred.calories - ref.calories)
    const ape = ref.calories > 0 ? abs / ref.calories : null
    const key = ape ?? Number.POSITIVE_INFINITY
    if (!best || key < best.key || (key === best.key && abs < best.abs)) best = { ref, ape, key, abs }
  }
  if (!best) throw new Error('bestRef: refs が空')
  return { ref: best.ref, ape: best.ape }
}

const FIELDS: Array<keyof Totals> = ['calories', 'protein_g', 'fat_g', 'carbs_g']
const within1 = (a: number, b: number) => Math.abs(a - b) <= 1

function all4Correct(r: RawRecord, refs: Totals[]): boolean {
  if (r.outcome !== 'ok' || !r.parsed) return false
  const p = r.parsed.totals
  return refs.some((ref) => FIELDS.every((f) => within1(p[f], ref[f])))
}

function normalizeAppName(s: string): string {
  return s.normalize('NFKC').toLowerCase().replace(/\s+/g, '')
}

function isGraded(e: Expected): boolean {
  return e.is_meal && e.totals !== null
}

type CaseMap = Map<string, DatasetSnapshot['cases'][number]>

function armMetrics(arm: ArmId, kind: InputKind, recs: RawRecord[], cases: CaseMap): ArmMetrics {
  const calls = recs.length
  const nonErr = recs.filter(isNonError)
  const mealCalls = nonErr.filter((r) => cases.get(r.case_id)?.expected.is_meal === true)
  const nonMealCalls = nonErr.filter((r) => cases.get(r.case_id)?.expected.is_meal === false)
  const lat = nonErr.map((r) => r.latency_ms).filter((x): x is number => typeof x === 'number')
  const costs = recs.map((r) => r.cost_usd).filter((x): x is number => typeof x === 'number')
  const meanCost = mean(costs)
  const priceCards: Record<string, number> = {}
  for (const r of recs) if (r.price_card) priceCards[r.price_card] = (priceCards[r.price_card] ?? 0) + 1

  const m: ArmMetrics = {
    arm,
    calls,
    parse_fail: rate(recs.filter((r) => r.outcome === 'parse_fail').length, calls),
    refusal: rate(recs.filter((r) => r.outcome === 'refusal').length, calls),
    max_tokens_stop: rate(recs.filter((r) => r.stop_reason === 'max_tokens').length, calls),
    error: rate(recs.filter((r) => r.outcome === 'error').length, calls),
    false_empty: rate(mealCalls.filter(isEmptyLike).length, mealCalls.length),
    correct_rejection: rate(nonMealCalls.filter(isEmptyLike).length, nonMealCalls.length),
    latency_p50_ms: quantile(lat, 0.5),
    latency_p90_ms: quantile(lat, 0.9),
    over_30s: rate(lat.filter((x) => x > PROD_TIMEOUT_MS).length, lat.length),
    mean_cost_usd: meanCost,
    mean_cost_jpy: meanCost === null ? null : meanCost * JPY_PER_USD,
    jpy_per_1000_calls: meanCost === null ? null : meanCost * JPY_PER_USD * 1000,
    total_cost_usd: costs.reduce((a, b) => a + b, 0),
    price_cards: priceCards,
  }

  if (kind === 'photo') {
    const apes: number[] = []
    const absK: number[] = []
    const absP: number[] = []
    const absF: number[] = []
    const absC: number[] = []
    let within = 0
    let nGraded = 0
    const perCaseCalories = new Map<string, number[]>()
    for (const r of nonErr) {
      const c = cases.get(r.case_id)
      if (!c || !isGraded(c.expected) || r.outcome !== 'ok' || !r.parsed) continue
      const pred = r.parsed.totals
      const { ref, ape } = bestRef(pred, refsOf(c.expected))
      nGraded++
      absK.push(Math.abs(pred.calories - ref.calories))
      absP.push(Math.abs(pred.protein_g - ref.protein_g))
      absF.push(Math.abs(pred.fat_g - ref.fat_g))
      absC.push(Math.abs(pred.carbs_g - ref.carbs_g))
      if (ape !== null) {
        apes.push(ape)
        if (ape <= 0.2) within++
      }
      const list = perCaseCalories.get(r.case_id) ?? []
      list.push(pred.calories)
      perCaseCalories.set(r.case_id, list)
    }
    const cvs = [...perCaseCalories.values()].map(coefficientOfVariation).filter((x): x is number => x !== null)
    m.photo = {
      n_calls_graded: nGraded,
      ape_median: median(apes),
      ape_p90: quantile(apes, 0.9),
      ape_mean: mean(apes),
      mae_kcal: mean(absK),
      within20: rate(within, apes.length),
      mae_protein_g: mean(absP),
      mae_fat_g: mean(absF),
      mae_carbs_g: mean(absC),
      cv_median: median(cvs),
      n_cases_cv: cvs.length,
    }
  } else {
    const fieldNum: Record<keyof Totals, number> = { calories: 0, protein_g: 0, fat_g: 0, carbs_g: 0 }
    let gradedCalls = 0
    let all4 = 0
    let warnNum = 0
    let warnDen = 0
    let fcNum = 0
    let fcDen = 0
    let appNum = 0
    let appDen = 0
    for (const r of nonErr) {
      const c = cases.get(r.case_id)
      if (!c) continue
      const e = c.expected
      if (isGraded(e)) {
        gradedCalls++
        const refs = refsOf(e)
        if (r.outcome === 'ok' && r.parsed) {
          const p = r.parsed.totals
          for (const f of FIELDS) if (refs.some((ref) => within1(p[f], ref[f]))) fieldNum[f]++
        }
        if (all4Correct(r, refs)) all4++
      }
      if (e.expect_warning !== undefined && e.expect_warning !== null) {
        warnDen++
        const predicted = r.outcome === 'ok' && r.warning !== null
        const answered = r.outcome === 'ok'
        if (answered && predicted === e.expect_warning) warnNum++
      }
      if (typeof e.foods_count === 'number') {
        fcDen++
        if (r.parsed && r.parsed.foods.length === e.foods_count) fcNum++
      }
      if (typeof e.app_name === 'string' && e.app_name.length > 0) {
        appDen++
        if (r.app_name && normalizeAppName(r.app_name) === normalizeAppName(e.app_name)) appNum++
      }
    }
    m.screenshot = {
      field_correct: {
        calories: rate(fieldNum.calories, gradedCalls),
        protein_g: rate(fieldNum.protein_g, gradedCalls),
        fat_g: rate(fieldNum.fat_g, gradedCalls),
        carbs_g: rate(fieldNum.carbs_g, gradedCalls),
      },
      all_four_correct: rate(all4, gradedCalls),
      warning_accuracy: rate(warnNum, warnDen),
      foods_count_exact: rate(fcNum, fcDen),
      app_name_match: rate(appNum, appDen),
    }
  }
  return m
}

function answers(recs: RawRecord[]): AnswerSummary[] {
  return recs
    .slice()
    .sort((a, b) => a.trial - b.trial)
    .map((r) => ({ trial: r.trial, outcome: r.outcome, totals: r.parsed?.totals ?? null, warning: r.warning }))
}

/** 写真: ケース → 平均 APE（ok 試行のみ） */
function perCaseMeanApe(recs: RawRecord[], c: DatasetSnapshot['cases'][number]): number | null {
  if (!isGraded(c.expected)) return null
  const apes: number[] = []
  for (const r of recs) {
    if (r.outcome !== 'ok' || !r.parsed) continue
    const { ape } = bestRef(r.parsed.totals, refsOf(c.expected))
    if (ape !== null) apes.push(ape)
  }
  return mean(apes)
}

/** スクショ: ケース → 4 項目同時正解率（API エラー以外の試行） */
function perCaseAll4(recs: RawRecord[], c: DatasetSnapshot['cases'][number]): number | null {
  if (!isGraded(c.expected)) return null
  const nonErr = recs.filter(isNonError)
  if (nonErr.length === 0) return null
  const refs = refsOf(c.expected)
  return nonErr.filter((r) => all4Correct(r, refs)).length / nonErr.length
}

const pct = (x: number | null) => (x === null ? 'n/a' : `${(x * 100).toFixed(1)}%`)

function compare(
  kind: InputKind,
  base: ArmMetrics,
  cand: ArmMetrics,
  byCaseArm: Map<string, Map<ArmId, RawRecord[]>>,
  cases: CaseMap,
): Comparison {
  const baseId = base.arm
  const candId = cand.arm
  const pairs: Array<{ case_id: string; b: number; c: number }> = []
  const candidate_failures: Comparison['candidate_failures'] = []
  for (const [caseId, arms] of byCaseArm) {
    const c = cases.get(caseId)
    if (!c) continue
    const br = arms.get(baseId) ?? []
    const cr = arms.get(candId) ?? []
    const f = kind === 'photo' ? perCaseMeanApe : perCaseAll4
    const bv = f(br, c)
    const cv = f(cr, c)
    if (bv !== null && cv !== null) pairs.push({ case_id: caseId, b: bv, c: cv })
    const candNonErr = cr.filter(isNonError)
    if (c.expected.is_meal && candNonErr.length > 0 && candNonErr.every((r) => r.outcome !== 'ok') && br.some((r) => r.outcome === 'ok')) {
      candidate_failures.push({ case_id: caseId, outcomes: cr.map((r) => r.outcome) })
    }
  }
  const deltas = pairs.map((p) => p.c - p.b)
  const clauses: Clause[] = []
  const reasons: string[] = []
  let verdict: Verdict
  const comp: Comparison = { candidate: candId, baseline: baseId, paired_cases: pairs.length, decision: { verdict: 'INSUFFICIENT DATA', clauses, reasons }, worst: [], candidate_failures }

  if (kind === 'photo') {
    const baseMed = median(pairs.map((p) => p.b))
    const candMed = median(pairs.map((p) => p.c))
    comp.photo = {
      base_median_ape: baseMed,
      cand_median_ape: candMed,
      delta_ape_median: bootstrapCI(deltas, (xs) => median(xs), { seed: BOOTSTRAP_SEED }),
    }
    const c1 = baseMed !== null && candMed !== null ? candMed <= 1.1 * baseMed : null
    clauses.push({
      label: '候補 median APE ≤ 1.10 × ベースライン median APE',
      pass: c1,
      detail: `候補 ${pct(candMed)} / 上限 ${baseMed === null ? 'n/a' : pct(1.1 * baseMed)}（ベースライン ${pct(baseMed)}）`,
    })
    const bfe = base.false_empty.value
    const cfe = cand.false_empty.value
    const c2 = bfe !== null && cfe !== null ? cfe <= bfe + 0.02 + 1e-12 : null
    clauses.push({
      label: '候補 false-EMPTY 率 ≤ ベースライン + 2pt',
      pass: c2,
      detail: `候補 ${pct(cfe)}（${cand.false_empty.num}/${cand.false_empty.den}） / 上限 ${bfe === null ? 'n/a' : pct(bfe + 0.02)}（ベースライン ${pct(bfe)}）`,
    })
  } else {
    const baseAll4 = mean(pairs.map((p) => p.b))
    const candAll4 = mean(pairs.map((p) => p.c))
    comp.screenshot = {
      base_all4: baseAll4,
      cand_all4: candAll4,
      delta_all4_mean: bootstrapCI(deltas, (xs) => mean(xs), { seed: BOOTSTRAP_SEED }),
    }
    const tol = 0.02 - 1e-12
    const mk = (label: string, b: number | null, c: number | null, cr: Rate | null): Clause => ({
      label,
      pass: b !== null && c !== null ? c >= b - tol : null,
      detail: `候補 ${pct(c)}${cr ? `（${cr.num}/${cr.den}）` : ''} / 下限 ${b === null ? 'n/a' : pct(b - 0.02)}（ベースライン ${pct(b)}）`,
    })
    clauses.push(mk('4 項目同時正解率 ≥ ベースライン − 2pt（ケース単位・対応あり）', baseAll4, candAll4, null))
    const bs = base.screenshot as ScreenshotMetrics
    const cs = cand.screenshot as ScreenshotMetrics
    clauses.push(mk('warning 正解率 ≥ ベースライン − 2pt', bs.warning_accuracy.value, cs.warning_accuracy.value, cs.warning_accuracy))
    clauses.push(mk('正しい拒否率（is_meal=false）≥ ベースライン − 2pt', base.correct_rejection.value, cand.correct_rejection.value, cand.correct_rejection))
  }

  if (pairs.length < MIN_GRADED_CASES) {
    verdict = 'INSUFFICIENT DATA'
    reasons.push(`対応ありで採点できたケースが ${pairs.length} 件（< ${MIN_GRADED_CASES}）`)
  } else if (clauses.some((c) => c.pass === null)) {
    verdict = 'INSUFFICIENT DATA'
    reasons.push(`評価できない条件あり: ${clauses.filter((c) => c.pass === null).map((c) => c.label).join(' / ')}`)
  } else {
    verdict = clauses.every((c) => c.pass) ? 'PASS' : 'FAIL'
  }
  comp.decision.verdict = verdict

  // 悪化の大きい上位 10%
  const sorted = pairs
    .map((p) => ({ ...p, delta: p.c - p.b }))
    .sort((x, y) => (kind === 'photo' ? y.delta - x.delta : x.delta - y.delta))
  const k = sorted.length === 0 ? 0 : Math.max(1, Math.ceil(sorted.length * 0.1))
  comp.worst = sorted.slice(0, k).map((p) => {
    const c = cases.get(p.case_id)!
    const arms = byCaseArm.get(p.case_id)!
    return {
      case_id: p.case_id,
      expected: c.expected.totals,
      n_alt_totals: c.expected.alt_totals?.length ?? 0,
      expect_warning: c.expected.expect_warning ?? null,
      baseline_value: p.b,
      candidate_value: p.c,
      delta: p.delta,
      baseline_answers: answers(arms.get(baseId) ?? []),
      candidate_answers: answers(arms.get(candId) ?? []),
    }
  })
  return comp
}

export function pareto(kind: InputKind, arms: ArmMetrics[]): ParetoRow[] {
  const rows: ParetoRow[] = arms.map((m) => ({
    arm: m.arm,
    score: kind === 'photo' ? (m.photo?.ape_median ?? null) : (m.screenshot?.all_four_correct.value ?? null),
    score_label: kind === 'photo' ? 'kcal APE 中央値（低いほど良い）' : '4 項目同時正解率（高いほど良い）',
    higher_is_better: kind !== 'photo',
    cost_jpy_per_call: m.mean_cost_jpy,
    on_frontier: false,
  }))
  const better = (a: number, b: number, hib: boolean) => (hib ? a > b : a < b)
  for (const r of rows) {
    if (r.score === null || r.cost_jpy_per_call === null) continue
    r.on_frontier = !rows.some(
      (o) =>
        o !== r &&
        o.score !== null &&
        o.cost_jpy_per_call !== null &&
        o.cost_jpy_per_call <= r.cost_jpy_per_call! &&
        (o.score === r.score || better(o.score, r.score!, r.higher_is_better)) &&
        (o.cost_jpy_per_call < r.cost_jpy_per_call! || better(o.score, r.score!, r.higher_is_better)),
    )
  }
  return rows
}

export function gradeRun(meta: RunMeta, snapshots: DatasetSnapshot[], rawRecords: RawRecord[], runDir = ''): Summary {
  const records = dedupeRecords(rawRecords)
  const armIds = meta.arms.map((a) => a.id)
  const baseline = meta.baseline_arm ?? BASELINE_ARM_ID
  const datasets: DatasetSummary[] = []
  for (const snap of snapshots) {
    const cases: CaseMap = new Map(snap.cases.map((c) => [c.id, c]))
    const recs = records.filter((r) => r.dataset === snap.name && cases.has(r.case_id))
    const byCaseArm = new Map<string, Map<ArmId, RawRecord[]>>()
    for (const r of recs) {
      const m = byCaseArm.get(r.case_id) ?? new Map<ArmId, RawRecord[]>()
      const l = m.get(r.arm) ?? []
      l.push(r)
      m.set(r.arm, l)
      byCaseArm.set(r.case_id, m)
    }
    const armsM = armIds.map((a) => armMetrics(a, snap.input_kind, recs.filter((r) => r.arm === a), cases))
    const baseM = armsM.find((m) => m.arm === baseline)
    const comparisons = baseM
      ? armsM.filter((m) => m.arm !== baseline).map((m) => compare(snap.input_kind, baseM, m, byCaseArm, cases))
      : []
    datasets.push({
      name: snap.name,
      input_kind: snap.input_kind,
      n_cases: snap.cases.length,
      n_graded_cases: snap.cases.filter((c) => isGraded(c.expected)).length,
      arms: armsM,
      comparisons,
      pareto: pareto(snap.input_kind, armsM),
    })
  }
  return {
    run_dir: runDir,
    generated_at: new Date().toISOString(),
    mock: meta.mock,
    baseline_arm: baseline,
    arms: armIds,
    jpy_per_usd: meta.jpy_per_usd ?? JPY_PER_USD,
    n_records: records.length,
    datasets,
  }
}
