/**
 * 本番 Edge Function のシステムプロンプトを「実行時に」ソースから抽出する。
 *
 * プロンプトを手でコピーすると本番と評価がずれるため、評価は常に
 * supabase/functions/estimate-meal-nutrition/index.ts の現在のテキストを使う。
 * テンプレートリテラル（`...`）を字句的に走査して取り出し、エスケープを JS と同じ規則で解決する。
 */
import { createHash } from 'node:crypto'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))

/** evals/meal-estimation のルート */
export const EVAL_ROOT = path.resolve(here, '..')
/** モノレポのルート（/home/user/fit-connect 相当） */
export const REPO_ROOT = path.resolve(EVAL_ROOT, '..', '..')
/** 本番 Edge Function のソース */
export const PRODUCTION_INDEX_PATH = path.join(
  REPO_ROOT,
  'supabase',
  'functions',
  'estimate-meal-nutrition',
  'index.ts',
)

export interface ProductionPrompts {
  /** SYSTEM_PROMPT（料理写真 = 推定） */
  photo: string
  /** SCREENSHOT_SYSTEM_PROMPT（他社アプリのスクショ = 数値読み取り） */
  screenshot: string
  sha256: { photo: string; screenshot: string; source_file: string }
  source_path: string
}

export function sha256(data: string | Buffer): string {
  return createHash('sha256').update(data).digest('hex')
}

/**
 * テンプレートリテラルの raw テキストを cooked 値に変換する（ECMAScript の TemplateCharacter 規則）。
 * ${...} を含むものは静的に評価できないので呼び出し側で拒否済み。
 */
function cookTemplate(raw: string, name: string): string {
  // テンプレート内のリテラル改行 CRLF / CR は LF に正規化される
  const src = raw.replace(/\r\n?/g, '\n')
  let out = ''
  for (let i = 0; i < src.length; i++) {
    const ch = src[i]
    if (ch !== '\\') {
      out += ch
      continue
    }
    const next = src[i + 1]
    i++
    switch (next) {
      case 'n': out += '\n'; break
      case 't': out += '\t'; break
      case 'r': out += '\r'; break
      case 'b': out += '\b'; break
      case 'f': out += '\f'; break
      case 'v': out += '\v'; break
      case '0': out += '\0'; break
      case '\n': break // 行継続
      case 'x': {
        const hex = src.slice(i + 1, i + 3)
        if (!/^[0-9a-fA-F]{2}$/.test(hex)) throw new Error(`${name}: invalid \\x escape`)
        out += String.fromCharCode(parseInt(hex, 16))
        i += 2
        break
      }
      case 'u': {
        if (src[i + 1] === '{') {
          const end = src.indexOf('}', i + 2)
          const hex = src.slice(i + 2, end)
          if (end === -1 || !/^[0-9a-fA-F]+$/.test(hex)) throw new Error(`${name}: invalid \\u{} escape`)
          out += String.fromCodePoint(parseInt(hex, 16))
          i = end
        } else {
          const hex = src.slice(i + 1, i + 5)
          if (!/^[0-9a-fA-F]{4}$/.test(hex)) throw new Error(`${name}: invalid \\u escape`)
          out += String.fromCharCode(parseInt(hex, 16))
          i += 4
        }
        break
      }
      case undefined:
        throw new Error(`${name}: dangling backslash`)
      default:
        // \` \$ \\ \' \" など: 文字そのもの
        out += next
    }
  }
  return out
}

/**
 * `const NAME = \`...\`` の中身を返す。見つからない・${} を含む・閉じていない場合は明示的に throw。
 */
export function extractTemplateLiteral(source: string, name: string, sourceLabel = 'source'): string {
  const re = new RegExp(`(?:^|\\n)[ \\t]*(?:export[ \\t]+)?const[ \\t]+${name}[ \\t]*(?::[^=\\n]+)?=[ \\t]*\``)
  const m = re.exec(source)
  if (!m) {
    throw new Error(
      `プロンプト抽出失敗: ${sourceLabel} に \`const ${name} = \\\`...\\\`\` のテンプレートリテラルが見つかりません。` +
        '本番コードの定義方法が変わった場合は src/prompts.ts を更新してください。',
    )
  }
  let raw = ''
  for (let i = m.index + m[0].length; i < source.length; i++) {
    const ch = source[i]
    if (ch === '\\') {
      raw += ch + (source[i + 1] ?? '')
      i++
      continue
    }
    if (ch === '`') return cookTemplate(raw, name)
    if (ch === '$' && source[i + 1] === '{') {
      throw new Error(`プロンプト抽出失敗: ${name} に \${...} 置換が含まれており静的に評価できません（${sourceLabel}）`)
    }
    raw += ch
  }
  throw new Error(`プロンプト抽出失敗: ${name} のテンプレートリテラルが閉じていません（${sourceLabel}）`)
}

/** ソーステキストから両プロンプトを抽出する（selftest からも使う純関数）。 */
export function extractPrompts(source: string, sourceLabel = 'source'): { photo: string; screenshot: string } {
  const photo = extractTemplateLiteral(source, 'SYSTEM_PROMPT', sourceLabel)
  const screenshot = extractTemplateLiteral(source, 'SCREENSHOT_SYSTEM_PROMPT', sourceLabel)
  // 最低限のサニティチェック: 両方とも JSON 形式指定（foods）を含むはず
  for (const [label, text] of [['SYSTEM_PROMPT', photo], ['SCREENSHOT_SYSTEM_PROMPT', screenshot]] as const) {
    if (text.trim().length < 50 || !text.includes('"foods"')) {
      throw new Error(`プロンプト抽出失敗: ${label} の内容が想定外です（"foods" を含まない／短すぎる）`)
    }
  }
  if (photo === screenshot) throw new Error('プロンプト抽出失敗: SYSTEM_PROMPT と SCREENSHOT_SYSTEM_PROMPT が同一です')
  return { photo, screenshot }
}

/** 本番 index.ts を読み、両プロンプトとハッシュを返す。 */
export function loadProductionPrompts(indexPath: string = PRODUCTION_INDEX_PATH): ProductionPrompts {
  let source: string
  try {
    source = readFileSync(indexPath, 'utf8')
  } catch (e) {
    throw new Error(`本番 Edge Function のソースを読めません: ${indexPath} (${(e as Error).message})`)
  }
  const { photo, screenshot } = extractPrompts(source, indexPath)
  return {
    photo,
    screenshot,
    sha256: { photo: sha256(photo), screenshot: sha256(screenshot), source_file: sha256(source) },
    source_path: indexPath,
  }
}
