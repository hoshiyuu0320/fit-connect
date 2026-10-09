/**
 * 採点結果を <runDir>/summary.json と <runDir>/report.md（日本語）に書き出す。
 *   npm run report -- runs/<dir>
 */
import { writeFileSync } from 'node:fs'
import path from 'node:path'
import { pathToFileURL } from 'node:url'
import { ARMS, type ArmId } from './arms.js'
import { gradeRun, loadRunDir, MIN_GRADED_CASES, PROD_TIMEOUT_MS, type ArmMetrics, type AnswerSummary, type DatasetSummary, type Rate, type Summary } from './grade.js'
import type { Totals } from './production-logic.js'
import type { RunMeta } from './run-types.js'

const pct = (x: number | null | undefined, d = 1) => (x === null || x === undefined ? 'n/a' : `${(x * 100).toFixed(d)}%`)
const num = (x: number | null | undefined, d = 1) => (x === null || x === undefined ? 'n/a' : x.toFixed(d))
const rt = (r: Rate | undefined) => (!r || r.den === 0 ? 'n/a' : `${pct(r.value)} (${r.num}/${r.den})`)
const ms = (x: number | null) => (x === null ? 'n/a' : `${(x / 1000).toFixed(1)}s`)
const totalsStr = (t: Totals | null) => (t ? `${t.calories}kcal P${t.protein_g} F${t.fat_g} C${t.carbs_g}` : '—')
const esc = (s: string) => s.replace(/\|/g, '\\|').replace(/\n/g, ' ')

function answersStr(as: AnswerSummary[], showWarning: boolean): string {
  if (as.length === 0) return '（記録なし）'
  return as
    .map((a) => {
      const body = a.outcome === 'ok' ? totalsStr(a.totals) : a.outcome
      const w = showWarning && a.outcome === 'ok' ? ` / warning:${a.warning ? 'あり' : 'なし'}` : ''
      return `t${a.trial}: ${body}${w}`
    })
    .join('<br>')
}

function table(header: string[], rows: string[][]): string {
  return [`| ${header.join(' | ')} |`, `| ${header.map(() => '---').join(' | ')} |`, ...rows.map((r) => `| ${r.join(' | ')} |`)].join('\n')
}

function armLabel(id: ArmId, baseline: ArmId): string {
  const a = ARMS[id]
  return `${id}${id === baseline ? '（基準）' : ''}`.concat(a ? `<br><sub>${a.model}</sub>` : '')
}

function qualityTable(ds: DatasetSummary, baseline: ArmId): string {
  return table(
    ['アーム', '呼出数', 'パース失敗', 'refusal', 'max_tokens停止', 'APIエラー', 'false-EMPTY (is_meal=true)', '正しい拒否 (is_meal=false)', 'レイテンシ p50 / p90', '30秒超', '平均コスト/回', '1000回あたり'],
    ds.arms.map((m: ArmMetrics) => [
      armLabel(m.arm, baseline),
      String(m.calls),
      rt(m.parse_fail),
      rt(m.refusal),
      rt(m.max_tokens_stop),
      rt(m.error),
      rt(m.false_empty),
      rt(m.correct_rejection),
      `${ms(m.latency_p50_ms)} / ${ms(m.latency_p90_ms)}`,
      rt(m.over_30s),
      m.mean_cost_usd === null ? 'n/a' : `$${m.mean_cost_usd.toFixed(5)}（${num(m.mean_cost_jpy, 3)}円）`,
      m.jpy_per_1000_calls === null ? 'n/a' : `${num(m.jpy_per_1000_calls, 0)}円`,
    ]),
  )
}

function photoTable(ds: DatasetSummary, baseline: ArmId): string {
  return table(
    ['アーム', '採点呼出', 'APE 中央値', 'APE p90', 'APE 平均', 'MAE kcal', '±20%以内', 'P MAE g', 'F MAE g', 'C MAE g', '試行間CV 中央値'],
    ds.arms.map((m) => {
      const p = m.photo!
      return [
        armLabel(m.arm, baseline),
        String(p.n_calls_graded),
        pct(p.ape_median),
        pct(p.ape_p90),
        pct(p.ape_mean),
        num(p.mae_kcal, 0),
        rt(p.within20),
        num(p.mae_protein_g),
        num(p.mae_fat_g),
        num(p.mae_carbs_g),
        p.n_cases_cv === 0 ? 'n/a' : `${pct(p.cv_median)}（${p.n_cases_cv}件）`,
      ]
    }),
  )
}

function screenshotTable(ds: DatasetSummary, baseline: ArmId): string {
  return table(
    ['アーム', 'カロリー', 'たんぱく質', '脂質', '炭水化物', '4項目同時', 'warning 正解', '品目数一致', 'アプリ名一致'],
    ds.arms.map((m) => {
      const s = m.screenshot!
      return [
        armLabel(m.arm, baseline),
        rt(s.field_correct.calories),
        rt(s.field_correct.protein_g),
        rt(s.field_correct.fat_g),
        rt(s.field_correct.carbs_g),
        rt(s.all_four_correct),
        rt(s.warning_accuracy),
        rt(s.foods_count_exact),
        rt(s.app_name_match),
      ]
    }),
  )
}

/** 差（割合の差）をパーセントポイントで表示 */
function ci(c: { estimate: number; lo: number; hi: number } | null): string {
  if (!c) return 'n/a'
  const f = (x: number) => `${x >= 0 ? '+' : ''}${(x * 100).toFixed(1)}pt`
  return `${f(c.estimate)}（95% CI ${f(c.lo)} 〜 ${f(c.hi)}）`
}

export function renderReport(summary: Summary, meta: RunMeta): string {
  const L: string[] = []
  const baseline = summary.baseline_arm
  L.push('# 食事栄養推定 モデル A/B 評価レポート')
  L.push('')
  if (summary.mock) {
    L.push('> **⚠ これは疑似応答（モック）による動作確認用の出力です。実測結果ではありません。数値を判断に使わないでください。**')
    L.push('')
  }
  L.push(`- 実行ディレクトリ: \`${summary.run_dir}\``)
  L.push(`- 実行期間: ${meta.started_at} 〜 ${meta.finished_at ?? '（未完了）'}${meta.resumed_at.length ? `（再開 ${meta.resumed_at.length} 回）` : ''}`)
  L.push(`- レポート生成: ${summary.generated_at}`)
  L.push(`- 試行回数: ${meta.args.trials} / ケース上限: ${meta.args.limit ?? 'なし'} / 記録数（重複除去後）: ${summary.n_records}`)
  L.push(`- 本番プロンプト: \`${meta.prompts.source_path}\`（SYSTEM_PROMPT sha256 \`${meta.prompts.sha256_photo.slice(0, 12)}\`、SCREENSHOT_SYSTEM_PROMPT sha256 \`${meta.prompts.sha256_screenshot.slice(0, 12)}\`）`)
  L.push(`- git HEAD: \`${meta.git.head ?? '不明'}\`${meta.git.production_file_dirty ? '（⚠ 本番 index.ts に未コミットの変更あり）' : ''}`)
  L.push(`- 為替: 1 USD = ${summary.jpy_per_usd} 円`)
  L.push('')
  L.push('## アーム')
  L.push('')
  L.push(
    table(
      ['アーム', 'model', 'max_tokens', 'temperature', 'effort', '画像ティア'],
      meta.arms.map((a) => [a.id + (a.id === baseline ? '（基準）' : ''), a.model, String(a.max_tokens), a.temperature === undefined ? '送らない' : String(a.temperature), a.effort ?? '送らない', a.vision_tier]),
    ),
  )
  L.push('')
  L.push('いずれのアームも `fallbacks`（サーバ側フォールバック）は送らない。refusal を「回避」せずに計測するため。')
  L.push('')

  // 判定サマリー
  L.push('## 判定サマリー（事前登録ルール）')
  L.push('')
  const rows: string[][] = []
  for (const ds of summary.datasets) {
    for (const c of ds.comparisons) {
      rows.push([
        `${ds.name}（${ds.input_kind === 'photo' ? '写真' : 'スクショ'}）`,
        c.candidate,
        `**${c.decision.verdict}**`,
        String(c.paired_cases),
        esc([...c.decision.clauses.map((x) => `${x.pass === null ? '－' : x.pass ? '✔' : '✘'} ${x.label}: ${x.detail}`), ...c.decision.reasons].join('<br>')),
      ])
    }
  }
  L.push(rows.length ? table(['データセット', '候補アーム', '判定', '対応ありケース数', '根拠'], rows) : '（比較対象なし: ベースラインアームが実行されていないか、記録がありません）')
  L.push('')
  L.push(`- 写真: 候補の kcal APE 中央値（ケース単位・試行平均・対応あり）≤ ベースラインの 1.10 倍 **かつ** false-EMPTY 率 ≤ ベースライン + 2pt → PASS`)
  L.push(`- スクショ: 4 項目同時正解率（ケース単位・対応あり）・warning 正解率・正しい拒否率がすべてベースライン − 2pt 以上 → PASS`)
  L.push(`- 対応ありで採点できたケースが ${MIN_GRADED_CASES} 件未満、または評価できない条件がある場合は INSUFFICIENT DATA`)
  L.push('')

  for (const ds of summary.datasets) {
    L.push(`## データセット: ${ds.name}（${ds.input_kind === 'photo' ? '料理写真 = 推定' : '他社アプリのスクショ = 読み取り'}）`)
    L.push('')
    L.push(`ケース数 ${ds.n_cases}（うち採点対象 ${ds.n_graded_cases}）`)
    L.push('')
    L.push('### 呼び出し品質・レイテンシ・コスト')
    L.push('')
    L.push(qualityTable(ds, baseline))
    L.push('')
    L.push('### 精度')
    L.push('')
    L.push(ds.input_kind === 'photo' ? photoTable(ds, baseline) : screenshotTable(ds, baseline))
    L.push('')
    if (ds.comparisons.length) {
      L.push('### ベースライン比較（ケース単位・対応あり）')
      L.push('')
      if (ds.input_kind === 'photo') {
        L.push(
          table(
            ['候補', '対応ありケース', 'ベースライン APE 中央値', '候補 APE 中央値', 'Δ APE 中央値（候補−基準）'],
            ds.comparisons.map((c) => [c.candidate, String(c.paired_cases), pct(c.photo?.base_median_ape ?? null), pct(c.photo?.cand_median_ape ?? null), ci(c.photo?.delta_ape_median ?? null)]),
          ),
        )
      } else {
        L.push(
          table(
            ['候補', '対応ありケース', 'ベースライン 4項目同時', '候補 4項目同時', 'Δ 平均（候補−基準）'],
            ds.comparisons.map((c) => [c.candidate, String(c.paired_cases), pct(c.screenshot?.base_all4 ?? null), pct(c.screenshot?.cand_all4 ?? null), ci(c.screenshot?.delta_all4_mean ?? null)]),
          ),
        )
      }
      L.push('')
      L.push(`ブートストラップ: ケースを復元抽出 ${ds.comparisons[0]?.photo?.delta_ape_median?.resamples ?? ds.comparisons[0]?.screenshot?.delta_all4_mean?.resamples ?? 2000} 回、シード固定、パーセンタイル法。`)
      L.push('')
      L.push('### 悪化の大きいケース（候補ごとに上位 10%）')
      L.push('')
      for (const c of ds.comparisons) {
        L.push(`#### ${c.candidate}`)
        L.push('')
        if (c.worst.length === 0) {
          L.push('（対応ありケースなし）')
        } else {
          L.push(
            table(
              ['ケース', '期待値', ds.input_kind === 'photo' ? 'APE 基準 → 候補' : '4項目正解率 基準 → 候補', 'ベースラインの回答', '候補の回答'],
              c.worst.map((w) => [
                esc(w.case_id),
                `${totalsStr(w.expected)}${w.n_alt_totals ? `（他 ${w.n_alt_totals} 通り可）` : ''}${w.expect_warning !== null ? `<br>warning 期待: ${w.expect_warning ? 'あり' : 'なし'}` : ''}`,
                `${pct(w.baseline_value)} → ${pct(w.candidate_value)}`,
                answersStr(w.baseline_answers, ds.input_kind === 'screenshot'),
                answersStr(w.candidate_answers, ds.input_kind === 'screenshot'),
              ]),
            ),
          )
        }
        if (c.candidate_failures.length) {
          L.push('')
          L.push(`候補が全試行で失敗し、ベースラインは成功したケース: ${c.candidate_failures.slice(0, 20).map((f) => `\`${f.case_id}\`（${f.outcomes.join(',')}）`).join('、')}${c.candidate_failures.length > 20 ? ` 他 ${c.candidate_failures.length - 20} 件` : ''}`)
        }
        L.push('')
      }
    }
    L.push('### スコア vs コスト（★ = パレート最適）')
    L.push('')
    L.push(
      table(
        ['アーム', ds.pareto[0]?.score_label ?? 'スコア', '平均コスト/回（円）', 'パレート'],
        ds.pareto.map((p) => [p.arm, pct(p.score), num(p.cost_jpy_per_call, 3), p.on_frontier ? '★' : '']),
      ),
    )
    L.push('')
  }

  L.push('## 定義・注意')
  L.push('')
  L.push('- **APIエラー**（タイムアウト・429・5xx など SDK の型付きエラー）は「APIエラー」列以外の分母から除外。')
  L.push('- **false-EMPTY**: is_meal=true のケースで foods が空（本番の EMPTY_RESULT）または refusal（feasibility §4-3 で EMPTY_RESULT に写像する想定）になった割合。**正しい拒否**は is_meal=false のケースで同じ状態になった割合。パース失敗は本番では 500（推定失敗）なので拒否には数えない。')
  L.push('- **写真の誤差**: パースに成功し foods が空でない呼び出しのみ。期待値は totals / alt_totals のうち APE 最小のもの。APE = |予測 kcal − 期待 kcal| / 期待 kcal。totals は本番どおり foods から再計算した値。')
  L.push('- **試行間 CV**: 同一ケースの成功試行の kcal の標本標準偏差 / 平均（2 試行以上成功したケースのみ）の中央値。')
  L.push('- **スクショの正答**: |予測 − 期待| ≤ 1。項目別は期待値候補のどれかと一致で正解、4 項目同時は同じ 1 つの期待値候補で 4 項目一致。ok 以外の呼び出しは不正解として分母に入る。warning は「ok かつ warning が非 null」を予測ありとみなす。')
  L.push(`- **レイテンシ**: 最後の HTTP 試行の開始からレスポンス解析完了まで（SDK のリトライ待ちは含まない）。本番は ${PROD_TIMEOUT_MS / 1000} 秒で abort するので「30秒超」は本番なら失敗になる呼び出し。評価では 60 秒まで待って計測する。`)
  L.push('- **コスト**: 実測 usage（input / cache 書き込み / cache 読み取り / output）× 料金表。Haiku 5.5 はリクエストごとのプロンプト長（input + cache 書き込み + cache 読み取り）が 100,000 を超えると高額カード。')
  L.push('- 画像は本番では署名 URL で渡すが、評価では同じ JPEG バイト列を base64 で送っている（URL 取得時間はレイテンシに含まれない）。')
  L.push('')
  return L.join('\n')
}

export async function generateReport(runDir: string): Promise<{ summaryPath: string; reportPath: string; summary: Summary }> {
  const { meta, snapshots, records } = loadRunDir(runDir)
  const summary = gradeRun(meta, snapshots, records, path.relative(process.cwd(), path.resolve(runDir)) || runDir)
  const summaryPath = path.join(runDir, 'summary.json')
  const reportPath = path.join(runDir, 'report.md')
  writeFileSync(summaryPath, JSON.stringify(summary, null, 2) + '\n')
  writeFileSync(reportPath, renderReport(summary, meta))
  return { summaryPath, reportPath, summary }
}

export function printVerdicts(summary: Summary, log: (s: string) => void = console.log): void {
  for (const ds of summary.datasets) {
    for (const c of ds.comparisons) {
      log(`  [${c.decision.verdict}] ${ds.name} ${c.candidate} vs ${c.baseline}（対応ありケース ${c.paired_cases}）`)
      for (const cl of c.decision.clauses) log(`      ${cl.pass === null ? '－' : cl.pass ? '✔' : '✘'} ${cl.label}: ${cl.detail}`)
      for (const r of c.decision.reasons) log(`      ・${r}`)
    }
  }
}

async function cli(): Promise<number> {
  const runDir = process.argv[2]
  if (!runDir) {
    console.error('使い方: npm run report -- runs/<dir>')
    return 2
  }
  const { summaryPath, reportPath, summary } = await generateReport(runDir)
  console.log(`summary: ${summaryPath}`)
  console.log(`report : ${reportPath}`)
  if (summary.mock) console.log('⚠ モック実行（実測ではありません）')
  printVerdicts(summary)
  return 0
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  cli().then(
    (code) => process.exit(code),
    (e) => {
      console.error((e as Error).message)
      process.exit(1)
    },
  )
}
