/** run.ts が書き、grade.ts / report.ts が読む成果物の型 */
import type { ArmConfig, ArmId } from './arms.js'
import type { DatasetSnapshot } from './dataset.js'
import type { Estimation, InputKind, Outcome } from './production-logic.js'

export interface RecordedError {
  /** SDK の型付きエラーから: 'timeout' | 'connection' | 'aborted' | API の error.type（例: 'rate_limit_error'）| クラス名 | 'internal' */
  type: string
  status: number | null
  message: string
}

/** raw.jsonl の 1 行（1 API 呼び出し） */
export interface RawRecord {
  /** `${dataset}::${case_id}::${arm}::${trial}` */
  key: string
  case_id: string
  dataset: string
  input_kind: InputKind
  arm: ArmId
  model: string
  trial: number
  started_at: string
  /** 最後の HTTP 試行の開始 → レスポンス本文の解析完了まで（本番の 30 秒 abort と比較する値） */
  latency_ms: number | null
  /** SDK のリトライ待ちを含む全体の所要時間 */
  total_ms: number
  /** HTTP 試行回数（1 = リトライなし） */
  attempts: number
  stop_reason: string | null
  stop_details: { category: string | null; explanation: string | null } | null
  response_model: string | null
  request_id: string | null
  /** SDK の usage オブジェクトそのまま（cache 系フィールドを含む） */
  usage: Record<string, unknown> | null
  price_card: string | null
  /** input + cache_creation + cache_read（Haiku 5.5 のレートカード判定値） */
  prompt_tokens: number | null
  cost_usd: number | null
  /** 最初の type==='text' ブロック */
  raw_text: string | null
  /** validateEstimation 後の結果 */
  parsed: Estimation | null
  parse_error: string | null
  app_name: string | null
  warning: string | null
  empty_result: boolean | null
  outcome: Outcome
  error: RecordedError | null
  /** latency_ms > 30000（本番は 30 秒で abort する） */
  prod_timeout_exceeded: boolean | null
}

export interface SerializableArgs {
  datasets: string[]
  arms: ArmId[]
  trials: number
  limit: number | null
  concurrency: number
  out: string
  resume: string | null
  estimate: boolean
  yes: boolean
  retry_errors: boolean
}

export interface RunMeta {
  schema_version: 1
  /** true = selftest 等の疑似応答（実測ではない） */
  mock: boolean
  args: SerializableArgs
  arms: Array<ArmConfig & { request_shape: Record<string, unknown> }>
  baseline_arm: ArmId
  prompts: { source_path: string; sha256_photo: string; sha256_screenshot: string; sha256_source_file: string }
  datasets: Array<{ name: string; input_kind: InputKind; cases_path: string; sha256: string; n_cases: number }>
  git: { head: string | null; production_file_dirty: boolean | null }
  sdk_version: string | null
  node_version: string
  jpy_per_usd: number
  started_at: string
  finished_at: string | null
  resumed_at: string[]
  counts: { planned: number; skipped_existing: number; executed: number; errors: number } | null
  notes: string[]
}

export type DatasetsSnapshotFile = DatasetSnapshot[]
